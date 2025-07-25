!#-------------------------------------- LICENCE BEGIN -------------------------
!Environment Canada - Atmospheric Science and Technology License/Disclaimer,
!                     version 3; Last Modified: May 7, 2008.
!This is free but copyrighted software; you can use/redistribute/modify it under the terms
!of the Environment Canada - Atmospheric Science and Technology License/Disclaimer
!version 3 or (at your option) any later version that should be found at:
!http://collaboration.cmc.ec.gc.ca/science/rpn.comm/license.html
!
!This software is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
!without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
!See the above mentioned License/Disclaimer for more details.
!You should have received a copy of the License/Disclaimer along with this software;
!if not, you can write to: EC-RPN COMM Group, 2121 TransCanada, suite 500, Dorval (Quebec),
!CANADA, H9P 1J3; or send e-mail to service.rpn@ec.gc.ca
!-------------------------------------- LICENCE END ----------------------------

module condensation
   implicit none
   private
   public :: condensation4

contains

   !/@*
   subroutine condensation4(pvars, dt, kount, ni, nk)
      use, intrinsic :: iso_fortran_env, only: REAL64
      use debug_mod, only: init2nan
      use tdpack_const, only: GRAV, DELTA, RGASD, CAPPA
      use phybudget, only: pb_compute, pb_conserve, pb_residual
      use microphy_utils, only: mp_lwc, mp_iwc
      use microphy_p3,  only: mp_p3_wrapper_gem, P3_OK=>STATUS_OK
      use microphy_p3v3,  only: mp_p3v3_wrapper_gem => mp_p3_wrapper_gem
      use microphy_kessler, only: kessler
      use microphy_consun, only: consun
      use microphy_s2, only: s2
      use microphy_my2, only: mp_my2_main
      use microphy_statcond, only: sc_adjust 
      use phy_options
      use phy_status, only: phy_error_L, PHY_OK
      use phybusidx
      use phymem, only: phyvar
      use tendency, only: apply_tendencies
      use water_integrated, only: wi_integrate
      implicit none
!!!#include <arch_specific.hf>
#include <rmnlib_basics.hf>
      !@Object Interface to convection/condensation
      !@Arguments
      type(phyvar), pointer, contiguous :: pvars(:)   !all phy vars (meta + slab data)
      integer, intent(in) :: ni                         !Row length
      integer, intent(in) :: nk                         !Number of levels (including diagnostic)
      real, intent(in) :: dt                            !Time step (s)
      integer, intent(in) :: kount                      !Step number

      !@Author L.Spacek, November 2011
      !@Revisions
      ! 001      new arguments in call to mydmom_main
      ! 002      PV-nov2014: fix communication between deep convection and MY_Dm
      !*@/
#include <rmn/msg.h>
      include "surface.cdk"
      include "phyinput.inc"

      ! Local parameters
      logical, parameter :: NK_BOTTOM = .true.  !(.T. for nk at bottom)
      integer, parameter :: N_DIAG_2D = 20      !number of diagnostic 2D fields
      integer, parameter :: N_DIAG_3D = 20      !number of diagnostic 3D fields

      ! Local variables
      integer :: nkm1, istat1, istat2
      real, dimension(ni,nk-1) :: iwc_total, lttp, lhup, &
           qtl, qts, fdqc, slw
      real, dimension(ni,N_DIAG_2D) :: diag_2d
      real, dimension(ni,nk-1,N_DIAG_3D) :: diag_3d
      real(REAL64), dimension(ni) :: l_en0, l_pw0

#define PHYPTRDCL
#include "condensation_ptr.hf"
      
      !----------------------------------------------------------------
      call msg_toall(MSG_DEBUG, 'condensation [BEGIN]')

      ! Basic configuration
      nkm1 = nk -1

#undef PHYPTRDCL
#include "condensation_ptr.hf"

      ! Initialize local variables
      call init2nan(iwc_total, lttp, lhup, slw)  
      call init2nan(qtl, qts, fdqc)
      call init2nan(l_en0, l_pw0)

      ! Startup operations
      if (kount == 0) then
         if (.not.any(phyinread_list_s(1:phyinread_n) == 'rhc')) zrhc(:,:) = -1.
      endif
      
      ! Local initializations
      if (associated(a_tls_fr1)) a_tls_fr1 = 0.
      if (associated(a_tls_fr2)) a_tls_fr2 = 0.
      
      ! Pre-scheme state for budget
      if (pb_compute(zconecnd, zconqcnd, l_en0, l_pw0, &
           pvars, nkm1) /= PHY_OK) then
         call physeterror('condensation', 'Problem computing preliminary budget')
         return
      endif

      ! Run selected gridscale condensation scheme
      GRIDSCALE_SCHEME: select case(stcond)

      case('KESSLER')

         ! Simple Kessler-based condensation scheme
         call kessler(zste, zsqe, zsqce, zsqre, a_tls, &
              ttp, qqp, qcp, qrp, zgztherm, sigma, psp, dt)
  
      case('CONSUN')

         ! Sundqvist-based condensation scheme
         call consun(zste, zsqe, zsqce, a_tls, a_tss, a_fxp, zrhc, &
              ttp, ttm, qqp, qqm, qcp, qcm, &
              psp, psm, sigma, dt, &
              zrnflx, zsnoflx, zf12, zfevp, zfice, &
              zpblsigs, zmrk2, ni, nkm1)

         ! Adjust tendencies to impose conservation
         if (pb_conserve(cond_conserve, zste, zsqe, pvars, &
              F_dqc=zsqce, F_rain=a_tls, F_snow=a_tss) /= PHY_OK) then
            call physeterror('condensation', &
                 'Cannot correct conservation for '//trim(stcond))
            return
         endif

      case ('S2')

         ! Pre-microphysics condensation adjustment
         call sc_adjust(ztcondc1, zqcondc1, zqccondc1, pvars, delt, ni, nkm1)
         
         ! Sundqvist-based microphysics scheme
         call s2(zste, zsqe, zsqce, a_tls, a_tss, a_fxp, zrhc, &
              ttp, ttm, qqp, qqm, qcp, qcm, &
              psp, psm, sigma, dt, &
              zrnflx, zsnoflx, zf12, zfevp, zfice, &
              zmrk2, ni, nkm1)

         ! Post-microphysics condensation adjustment

      case('MP_MY2')
         
         ! Milbrandt-Yau 2-moment microphysics
         call mp_my2_main(zste, zsqe, zsqce, zsqre, &
              ww,ttp,qqp,qcp,qrp,qip,qnp,qgp,qhp,ncp,nrp,nip,nnp,ngp,nhp,a_nwfa,     &
              psp, sigma, a_tls, a_tls_rn1, a_tls_rn2, a_tls_fr1, a_tls_fr2, a_tss, a_tss_sn1,   &
              a_tss_sn2, a_tss_sn3, a_tss_pe1, a_tss_pe2, a_tss_pe2l, a_tss_snd,dt, ni, nkm1, 1, &
              kount, mp_aeroact, my_ccntype, my_diagon, my_sedion, my_warmon, my_rainon,         &
              my_iceon, my_snowon, a_dm_c,a_dm_r,a_dm_i,a_dm_s,a_dm_g,a_dm_h, a_zet, a_zec,      &
              diag_3d, a_effradc, a_effradi1, a_effradi2, a_effradi3, a_effradi4, a_fxp,         &
              NK_BOTTOM)
         if (phy_error_L) return
          
      case('MP_P3V3')
         
         ! Predicted Particle Properties (P3) microphysics
         istat1 = mp_p3v3_wrapper_gem(zste,zsqe,zsqce,zsqre,qitend, &
              qqm,qqp,ttm,ttp,dt,p3_dtmax,ww,psp,zgztherm,sigma,   &
              kount,ni,nkm1,a_tls,a_tss,a_tls_rn1,a_tls_rn2,a_tss_sn1,          &
              a_tss_sn2,a_tss_sn3,a_tss_pe1,a_tss_pe2,a_tss_snd,a_zet,a_zec,          &
              a_effradc,qcp,ncp,qrp,nrp,N_DIAG_2D,diag_2d,N_DIAG_3D,diag_3d,  &
              p3_depfact,p3_subfact,p3_debug,a_h_cb,a_h_sn,a_vis,a_vis1,      &
              a_vis2,a_vis3,slw,p3_scpf_on,p3_pfrac,p3_resfact,a_fxp,               &
              a_qi_1,a_qi_2,a_qi_3,a_qi_4,a_qi_5,a_qi_6, &
              qti1p,qmi1p,nti1p,bmi1p,a_effradi1,qti2p,qmi2p,nti2p,bmi2p,a_effradi2,  &
              qti3p,qmi3p,nti3p,bmi3p,a_effradi3,qti4p,qmi4p,nti4p,bmi4p,a_effradi4)
         if (istat1 /= P3_OK) then
            call physeterror('condensation', 'Error returned by P3v3 gem wrapper')
            return
         endif

         ! Adjust tendencies to impose conservation
         if (pb_conserve(cond_conserve, zste, zsqe, pvars, &
              F_dqc=zsqce+zsqre, F_dqi=qitend, F_rain=a_tls, F_snow=a_tss) /= PHY_OK) then
            call physeterror('condensation', &
                 'Cannot correct conservation for '//trim(stcond))
            return
         endif
         
      case('MP_P3')
         
         ! Predicted Particle Properties (P3) microphysics
         istat1 = mp_p3_wrapper_gem(zste,zsqe,zsqce,zsqre,qitend,                                                          &
              qqm,qqp,ttm,ttp,dt,p3_dtmax,ww,psp,zgztherm,zgzmom,sigma,                                                    &
              kount,ni,nkm1,a_tls,a_tss,a_tls_rn1,a_tls_rn2,a_tss_sn1,                                                     &
              a_tss_sn2,a_tss_sn3,a_tss_pe1,a_tss_pe2,a_tss_snd,a_tss_ws,                                                  &
              a_zet,a_zec,a_effradc,qcm,qcp,ncp,qrm,qrp,nrp,N_DIAG_2D,diag_2d,N_DIAG_3D,diag_3d,                           &
              p3_depfact,p3_subfact,p3_debug,a_h_cb,a_h_sn,a_vis,a_vis1,                                                   &
              a_vis2,a_vis3,slw,p3_scpf_on,p3_pfrac,p3_resfact,a_fxp,a_diag_dhmax,                                         &
              a_qi_1,a_qi_2,a_qi_3,a_qi_4,a_qi_5,a_qi_6,                                                                   &
              qti1m,qti1p,qmi1p,nti1p,bmi1p,a_effradi1,zitot_1=zti1p,qiliq_1=qli1p,                                        &
              qitot_2m=qti2m,qitot_2=qti2p,qirim_2=qmi2p,nitot_2=nti2p,birim_2=bmi2p,diag_effi_2=a_effradi2,zitot_2=zti2p,qiliq_2=qli2p,  &
              qitot_3m=qti3m,qitot_3=qti3p,qirim_3=qmi3p,nitot_3=nti3p,birim_3=bmi3p,diag_effi_3=a_effradi3,zitot_3=zti3p,qiliq_3=qli3p,  &
              qitot_4m=qti4m,qitot_4=qti4p,qirim_4=qmi4p,nitot_4=nti4p,birim_4=bmi4p,diag_effi_4=a_effradi4,zitot_4=zti4p,qiliq_4=qli4p)
         if (istat1 /= P3_OK) then
            call physeterror('condensation', 'Error returned by P3 gem wrapper')
            return
         endif

         ! Adjust tendencies to impose conservation
         if (pb_conserve(cond_conserve, zste, zsqe, pvars, &
              F_dqc=zsqce+zsqre, F_dqi=qitend, F_rain=a_tls, F_snow=a_tss) /= PHY_OK) then
            call physeterror('condensation', &
                 'Cannot correct conservation for '//trim(stcond))
            return
         endif

      end select GRIDSCALE_SCHEME

      ! Split diagnostic tables into the bus
      if (associated(a_d2d01)) then
         a_d2d01 = diag_2d(:,1);    a_d2d08 = diag_2d(:, 8);    a_d2d15 = diag_2d(:,15)
         a_d2d02 = diag_2d(:,2);    a_d2d09 = diag_2d(:, 9);    a_d2d16 = diag_2d(:,16)
         a_d2d03 = diag_2d(:,3);    a_d2d10 = diag_2d(:,10);    a_d2d17 = diag_2d(:,17)
         a_d2d04 = diag_2d(:,4);    a_d2d11 = diag_2d(:,11);    a_d2d18 = diag_2d(:,18)
         a_d2d05 = diag_2d(:,5);    a_d2d12 = diag_2d(:,12);    a_d2d19 = diag_2d(:,19)
         a_d2d06 = diag_2d(:,6);    a_d2d13 = diag_2d(:,13);    a_d2d20 = diag_2d(:,20)
         a_d2d07 = diag_2d(:,7);    a_d2d14 = diag_2d(:,14)
      endif
      if (associated(a_ss01)) then
         a_ss01 = diag_3d(:,:,1);   a_ss08 = diag_3d(:,:, 8);   a_ss15 = diag_3d(:,:,15)
         a_ss02 = diag_3d(:,:,2);   a_ss09 = diag_3d(:,:, 9);   a_ss16 = diag_3d(:,:,16)
         a_ss03 = diag_3d(:,:,3);   a_ss10 = diag_3d(:,:,10);   a_ss17 = diag_3d(:,:,17)
         a_ss04 = diag_3d(:,:,4);   a_ss11 = diag_3d(:,:,11);   a_ss18 = diag_3d(:,:,18)
         a_ss05 = diag_3d(:,:,5);   a_ss12 = diag_3d(:,:,12);   a_ss19 = diag_3d(:,:,19)
         a_ss06 = diag_3d(:,:,6);   a_ss13 = diag_3d(:,:,13);   a_ss20 = diag_3d(:,:,20)
         a_ss07 = diag_3d(:,:,7);   a_ss14 = diag_3d(:,:,14)
      endif

      !Application of standard microphysical tendencies
      call apply_tendencies(ttp,  qqp, &
           &                zste, zsqe, ztdmaskxdt, ni, nk, nkm1)
      if (associated(qcp)) call apply_tendencies(qcp, zsqce, ztdmaskxdt, ni, nk, nkm1)
      if (associated(qrp)) call apply_tendencies(qrp, zsqre, ztdmaskxdt, ni, nk, nkm1)

      !# TODO: automate that clipping with info from gesdict
      if (stcond(1:5) == 'MP_P3') then
         ! call priv_check_negative(qqp, 0., 'huplus')
         qqp = max(0., qqp)
         if (associated(qcp)) then
            ! call priv_check_negative(qcp, 0., 'qcplus')
            qcp = max(0., qcp)
         endif
         if (associated(qrp)) then
            ! call priv_check_negative(qrp, 0., 'qrplus')
            qrp = max(0., qrp)
         endif
      endif

      ! Post-scheme budget analysis: post-scheme state and residuals
      if (pb_residual(zconecnd, zconqcnd, l_en0, l_pw0, pvars, &
           delt, nkm1, F_rain=a_tls, F_snow=a_tss) /= PHY_OK) then
         call physeterror('condensation', 'Problem computing final budget')
         return
      endif

      ! Post-scheme condensation adjustment
      if (stcond == 'S2') &
           call sc_adjust(ztcondc1, zqcondc1, zqccondc1, pvars, delt, ni, nkm1)
      
      ! Compute profile diagnostics <<< should be done outside the model >>>
      istat1 = mp_lwc(qtl, pvars)
      istat2 = mp_iwc(qts, pvars)
      if (istat1 /= PHY_OK .or. istat2 /= PHY_OK) then
         call physeterror('condensation', &
              'Cannot compute water/ice for hydrometeor integrals')
         return
      endif
      call wi_integrate(ttp, qqp, qtl, qts, sigma, psp, zicw, ziwv, ziwv700, &
           ziwp, zlwp2, zslwp, zslwp2, zslwp3, zslwp4, ni, nkm1)

      call msg_toall(MSG_DEBUG, 'condensation [END]')
      !----------------------------------------------------------------
      return
   end subroutine condensation4

   
!!$   subroutine priv_check_negative(F_fld, F_minval, F_name)
!!$      implicit none
!!$      real, pointer, contiguous :: F_fld(:,:)
!!$      real, intent(in) :: F_minval
!!$      character(len=*), intent(in) :: F_name
!!$      real :: x
!!$      !----------------------------------------------------------------
!!$      x = minval(F_fld)
!!$      if ((F_minval - x) > abs(x)*epsilon(x)) &
!!$           call msg_toall(MSG_WARNING, '(condensation) Post P3 Negative values for: '//trim(F_name))
!!$      !----------------------------------------------------------------
!!$      return
!!$   end subroutine priv_check_negative

end module condensation
