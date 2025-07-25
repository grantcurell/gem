!---------------------------------- LICENCE BEGIN -------------------------------
! GEM - Library of kernel routines for the GEM numerical atmospheric model
! Copyright (C) 1990-2010 - Division de Recherche en Prevision Numerique
!                       Environnement Canada
! This library is free software; you can redistribute it and/or modify it 
! under the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, version 2.1 of the License. This library is
! distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
! without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
! You should have received a copy of the GNU Lesser General Public License
! along with this library; if not, write to the Free Software Foundation, Inc.,
! 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
!---------------------------------- LICENCE END ---------------------------------

module phy_step_mod
   private
   public :: phy_step

contains

  !/@*
  function phy_step (F_stepcount, F_stepdriver) result(F_istat)
    use wb_itf_mod, only: WB_OK, WB_IS_OK, wb_get
    use clib_itf_mod, only: clib_toupper
    use str_mod, only: str_concat
    use series_mod, only: series_stepinit, series_stepend
    use phy_status, only: phy_error_L, phy_init_ctrl, PHY_CTRL_INI_OK, PHY_NONE
    use phy_options, only: delt, sgo_tdfilter, lhn_filter, sfcflx_filter_order, debug_initonly_L, nphyoutlist, nphystepoutlist, phyoutlist_S, phystepoutlist_S
    use phygridmap, only: phydim_ni, phydim_nj, phydim_nk
    use physlb, only: physlb1
    use phymem, only: phymem_find_idxv, phymem_getmeta, phymeta

#ifdef HAVE_NEMO
    use cpl_itf   , only: cpl_step
#endif

    use ens_perturb, only: ens_spp_stepinit, ENS_OK
    implicit none

    !@objective Apply the physical processes: CMC/RPN package
    integer, intent(in) :: F_stepcount     !Step kount incrementing from 0
    integer, intent(in) :: F_stepdriver    !Step number of the driving model
    integer :: F_istat                     !Return status (RMN_OK or RMN_ERR)

    !@authors Desgagne, Chamberland, McTaggart-Cowan, Spacek -- Spring 2014

    !@revision
    !*@/
#include <rmnlib_basics.hf>
!!!#include <arch_specific.hf>
#include <rmn/msg.h>

    include "physteps.cdk"

    integer, external :: phyput_input_param, sfc_get_input_param

    integer, save :: pslic
    logical, save :: do_phyoutlist_L = .true.

    character(len=1024) :: msg_S, list_S
    integer :: istat, sfcflxfilt, itmp, nn, n, idxlist(1)
    real :: gwd_sig, lhn_sig
    type(phymeta), pointer    :: vmeta
    !---------------------------------------------------------------
    F_istat = RMN_ERR
    if (phy_init_ctrl == PHY_NONE) then
       F_istat = PHY_NONE
       return
    else if (phy_init_ctrl /= PHY_CTRL_INI_OK) then
       call msg(MSG_ERROR,'(phy_step) Physics not properly initialized.')
       return
    endif
    
    if (debug_initonly_L) then
       call msg(MSG_WARNING,'(phy_step) debug_initonly_L - skipping')
       F_istat = RMN_OK
       return
    endif

    IF_KOUNT0: if (F_stepcount == 0) then
      if (.not.WB_IS_OK(wb_get('dyn/sgo_tdfilter',gwd_sig))) gwd_sig = -1.
      if (sgo_tdfilter /= gwd_sig) then
         call msg(MSG_ERROR, '(phy_step) sgo_tdfilter requested in but not supported by dyn')
         return
      endif
      if (.not.WB_IS_OK(wb_get('dyn/lhn_filter', lhn_sig))) lhn_sig = -1.
      if (lhn_filter /= lhn_sig) then
         call msg(MSG_ERROR, '(phy_step) lhn_filter requested in but not supported by dyn')
         return
      endif
      if (.not.WB_IS_OK(wb_get('dyn/sfcflx_filter_order', sfcflxfilt))) sfcflxfilt = -1
      if (sfcflx_filter_order /= sfcflxfilt) then
         call msg(MSG_ERROR, '(phy_step) sfcflx_filter_order requested in but not supported by dyn')
         return
      endif
    endif IF_KOUNT0

    istat = series_stepinit(F_stepcount)
    if (.not.RMN_IS_OK(istat)) &
         call msg(MSG_ERROR,'(phy_step) Problem in series step init')

    if (ens_spp_stepinit(F_stepcount) /= ENS_OK) &
         call msg(MSG_ERROR,'(phy_step) Problem in ensemble step init')

    if (.not.associated(phystepoutlist_S)) &
         allocate(phystepoutlist_S(max(1,nphyoutlist)))
    istat = wb_get('itf_phy/PHYSTEPOUT_N', nphystepoutlist)
    if (.not.WB_IS_OK(istat)) nphystepoutlist = 0
    if (nphystepoutlist > 0) then
       istat = wb_get('itf_phy/PHYSTEPOUT_V', phystepoutlist_S, itmp)
       if (.not.WB_IS_OK(istat)) nphystepoutlist = 0
       do n=1,nphystepoutlist
          nn = phymem_find_idxv(idxlist, phystepoutlist_S(n), F_npath='VO', F_bpath='EPVD', F_quiet=.true.)
          if (nn > 0) istat = phymem_getmeta(vmeta, idxlist(1))
          if (nn > 0 .and. RMN_IS_OK(istat)) then
             phystepoutlist_S(n) = vmeta%oname(1:4)
             istat = clib_toupper(phystepoutlist_S(n))
          endif
       enddo
    endif
    if (nphyoutlist > 0 .and. do_phyoutlist_L) then
       do_phyoutlist_L = .false.
       do n=1,nphyoutlist
          nn = phymem_find_idxv(idxlist, phyoutlist_S(n), F_npath='VO', F_bpath='EPVD', F_quiet=.true.)
          if (nn > 0) istat = phymem_getmeta(vmeta, idxlist(1))
          if (nn > 0 .and. RMN_IS_OK(istat)) then
             phyoutlist_S(n) = vmeta%oname(1:4)
             istat = clib_toupper(phyoutlist_S(n))
          endif
       enddo
    endif
    ! if (nphystepoutlist == 0) then
    !    list_S = '[No phy output requested for this step]'
    ! else
    !    call str_concat(list_S, phystepoutlist_S(1:nphystepoutlist), ', ')
    ! endif
    ! write(msg_S, '(a, i8,a,i4,a)') '[step=', F_stepdriver, '] (1:', nphystepoutlist, ')'
    ! call msg(MSG_INFOPLUS, 'Phy Out Vars '//trim(msg_S)//': '//trim(list_S))

    pslic = 0
    step_kount  = F_stepcount
    step_driver = F_stepdriver
    istat = WB_OK
    istat = min(phyput_input_param(),istat)
    istat = min(sfc_get_input_param(),istat)
    if (istat /= WB_OK) call msg(MSG_ERROR,'(phy_step)')

#ifdef HAVE_NEMO
    call cpl_step(F_stepcount, F_stepdriver)
#endif

!$omp parallel
    call physlb1(F_stepcount, phydim_ni, phydim_nj, phydim_nk, pslic)
!$omp end parallel
    if (phy_error_L) return

    istat = series_stepend()
    if (.not.RMN_IS_OK(istat)) &
         call msg(MSG_ERROR,'(phy_step) Problem in series step end')

    if (phy_error_L) return

    call timing_start2(460, 'phystats', 46)
    call phystats(F_stepcount, delt)
    call timing_stop(460)
    if (phy_error_L) return

    F_istat = RMN_OK
    !---------------------------------------------------------------
    return
  end function phy_step

end module phy_step_mod

