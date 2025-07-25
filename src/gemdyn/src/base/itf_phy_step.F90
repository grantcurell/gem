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

!**s/r itf_phy_step - Apply the physical processes: CMC/RPN package

      subroutine itf_phy_step ( F_step_kount, F_lctl_step )
      use iso_c_binding
      use phy_itf, only: PHY_MAXNAMELENGTH, phymeta, phy_input1, phy_step,phy_snapshot, phy_getmeta, phy_putmeta
      use itf_phy_cloud_objects, only: cldobj_displace,cldobj_expand,CLDOBJ_OK
      use itf_phy_filter, only: ipf_smooth_fld, sfcflxfilt_o, nsurfag
      use init_options
      use lun
      use tr3d
      use rstr
      use path
      use wb_itf_mod
      use clib_itf_mod
      use ptopo
      use omp_timing
      use gmm_phy, only: phy_cplm, phy_cplt
      use dyn_fisl_options, only: Schm_phycpl_S, Cstv_bA_8, Cstv_bA_m_8, Schm_wload_L
      use phy_itf, only: phy_get,phy_put
      use ens_options, only: ens_skeb_tndfix
      implicit none
#include <arch_specific.hf>

      integer, intent(in) :: F_step_kount, F_lctl_step

!arguments
!  Name                    Description
!----------------------------------------------------------------
! F_step_kount             step count
! F_lctl_step              step number
!----------------------------------------------------------------

      include "rpn_comm.inc"

      integer,external :: itf_phy_prefold_opr

      integer :: err_geom, err_input, err_step, err_smooth, err
      logical :: cloudobj

      real, dimension(:,:,:), pointer :: zud, zvd

!
!     ---------------------------------------------------------------
!
      if ( Rstri_user_busper_L .and. (F_step_kount == 0) ) return

      call gtmg_start ( 40, 'PHYSTEP', 1 )

      if (Lun_out > 0) write (Lun_out,1001) F_lctl_step

      if (F_step_kount == 0) then
         call itf_phy_geom (err_geom)
         if (NTR_Tr3d_ntr > 0) then
            err = wb_put('itf_phy/READ_TRACERS', &
                                NTR_Tr3d_name_S(1:NTR_Tr3d_ntr))
         end if
         select case (Schm_phycpl_S)
         case ('RHS')
            phy_cplm(:,:) = 0.
            phy_cplt(:,:) = 0.
         case ('AVG')
            phy_cplm(:,:) = Cstv_bA_m_8
            phy_cplt(:,:) = Cstv_bA_8
         case DEFAULT
            phy_cplm(:,:) = 1.
            phy_cplt(:,:) = 1.
         end select

         call priv_update_tracers_meta()
      end if

      !call pw_glbstat('PW_BEF')

      call gtmg_start ( 41, 'PHY_COPY', 40)
      call itf_phy_copy ()
      !if (F_step_kount == 0) call itf_phy_glbstat('befinp')
      call gtmg_stop  ( 41 )

      call gtmg_start ( 42, 'PHY_input', 40 )
      err_input = phy_input1 ( itf_phy_prefold_opr, F_step_kount, &
            Path_phyincfg_S, Path_phy_S, 'GEOPHY/Gem_geophy.fst' )
      !if (F_step_kount == 0) call itf_phy_glbstat('Aftinp')
      call gem_error (err_input,'itf_phy_step','Problem with phy_input')
      call gtmg_stop  ( 42 )

      call gtmg_start ( 43, 'PHY_SMOOTH', 40)
      ! Smooth the thermodynamic state variables on request
      err_smooth = min(&
           ipf_smooth_fld('rt',   'rt_smt',   3, 1), &
           ipf_smooth_fld('rdpr', 'rdpr_smt', 3, 1), &
           ipf_smooth_fld('rdqi', 'rdqi_smt', 3, 1), &
           ipf_smooth_fld('tcond','tcond_smt',3) &
           )
      call gem_error (err_smooth,'itf_phy_step','Problem with ipf_smooth_fld')
      call gtmg_stop  ( 43 )

      ! Call digital filter to smooth Alfa, Beta surface fields
      call gtmg_start ( 44, 'PHY_DFILTER', 40)
      if (sfcflxfilt_o > 1 .and. F_step_kount > 0) then
         call dfilter('alfat','falfat',1)
         call dfilter('alfaq','falfaq',1)
         call dfilter('bt','fbt',nsurfag)
      endif
      call gtmg_stop  ( 44 )

      ! Advect cloud objects
      call gtmg_start ( 45, 'PHY_CLDOBJ', 40)
      if (.not.WB_IS_OK(wb_get('phy/deep_cloudobj',cloudobj))) cloudobj = .false.
      if (cloudobj .and. F_lctl_step > 0) then
         if (cldobj_displace() /= CLDOBJ_OK) then
              call gem_error (-1,'itf_phy_step','Problem with cloud object displacement')
         endif
      endif
      call gtmg_stop  ( 45 )

      call itf_phy_output_list(F_lctl_step)
      
      call set_num_threads ( Ptopo_nthreads_phy, F_step_kount )
      !call itf_phy_glbstat('befphy')

      call gtmg_start ( 46, 'PHY_step', 40 )
      err_step = phy_step ( F_step_kount, F_lctl_step )
!      call rpn_comm_barrier (RPN_COMM_ALLGRIDS, err)
      call gtmg_stop  ( 46 )

      call gem_error (err_step,'itf_phy_step','Problem with phy_step')
      !call itf_phy_glbstat('aftphy')

      call set_num_threads ( Ptopo_nthreads_dyn, F_step_kount )

      call gtmg_start ( 47, 'PHY_update', 40 )
      call itf_phy_update3 ( F_step_kount > 0 )
      call gtmg_stop  ( 47 )
      !call pw_glbstat('PW_AFT')

      call gtmg_start ( 48, 'PHY_output', 40 )
      call itf_phy_output ( F_lctl_step )
      call gtmg_stop  ( 48 )

      call gtmg_start ( 49, 'PHY_DIAG', 40 )
      call itf_phy_diag ()
      call gtmg_stop  ( 49 )

      if ( Init_mode_L ) then
         if (F_step_kount ==   Init_halfspan) then
            err = phy_snapshot('W')
         else if (F_step_kount == 2*Init_halfspan) then
            if (.not. ens_skeb_tndfix) then
               nullify(zud, zvd)
               err = phy_get(zud, 'phytd_udis', F_npath='V', F_bpath='P')
               err = min(err, phy_get(zvd, 'phytd_vdis', F_npath='V', F_bpath='P'))
               call gem_error (err, 'itf_phy_step', 'Cannot retrieve dissipations')
            endif
            err = phy_snapshot('R')
            if (.not. ens_skeb_tndfix) then
               err = phy_put(zud, 'phytd_udis', F_npath='V', F_bpath='P')
               err = min(err, phy_put(zvd, 'phytd_vdis', F_npath='V', F_bpath='P'))
               call gem_error (err, 'itf_phy_step', 'Cannot reset dissipations')
               deallocate(zud, zvd)
            endif
         end if
      end if

      call gtmg_stop ( 40 )

      return

1001  format(/,'PHYSICS : PERFORMING TIMESTEP #',I9, &
             /,'========================================')
!
!     ---------------------------------------------------------------
!

   contains

      subroutine priv_update_tracers_meta()
      implicit none
      integer :: i, j, i1, istat, nmeta
      character(len=PHY_MAXNAMELENGTH) :: varname_S,prefix_S, &
                                          basename_S,time_S,ext_S
      type(phymeta), dimension(:), pointer :: pmeta
         
      nmeta= 0 ; nullify(pmeta)
      nmeta = phy_getmeta(pmeta, 'TR/', F_npath='V', F_bpath='D', &
           F_quiet=.true., F_shortmatch=.true.)

      do i=1,nmeta
         varname_S = pmeta(i)%vname
         istat = clib_toupper(varname_S)
         call gmmx_name_parts(varname_S, prefix_S, basename_S, time_S, ext_S)
         if (time_S/=':P') cycle
         i1 = 0
         do j=1,Tr3d_ntr
            if (trim(Tr3d_name_S(j)) == basename_S) i1 = j
         end do
         if (i1 /= 0) then
            pmeta(i)%hzd = Tr3d_hzd(i1)
            pmeta(i)%wload = Tr3d_wload(i1) .and. Schm_wload_L
            pmeta(i)%monot = Tr3d_mono(i1)
            pmeta(i)%massc = Tr3d_mass(i1)
            pmeta(i)%vmin = Tr3d_vmin(i1)
            pmeta(i)%vmax = Tr3d_vmax(i1)
!!$            pmeta(i)% = Tr3d_intp(i1)
            istat = phy_putmeta(pmeta(i), pmeta(i)%vname, F_npath='V', F_bpath='D', F_quiet=.true.)
         endif
      end do
      if (associated(pmeta)) deallocate(pmeta)
         
      return
      end subroutine priv_update_tracers_meta
      
      end subroutine itf_phy_step
