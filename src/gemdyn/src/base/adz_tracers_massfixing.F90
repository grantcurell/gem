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

      subroutine adz_tracers_massfixing ()
      use ens_options
      use adz_interp_hlt_mod
      use mem_tracers
      use omp_timing
      implicit none

      integer ::  n, deb
!
!     ---------------------------------------------------------------
!
      call gtmg_start (55, 'C_massfix', 10)
      
      !Resetting done at each timestep before calling adz_post_tr
      !----------------------------------------------------------
      if (max(Tr3d_ntrTRICUB_WP,Tr3d_ntrBICHQV_WP)>0) call set_post_tr_hlt ()

      call gtmg_start (57, 'C_TR_POST', 55)
      if (Tr3d_ntrTRICUB_WP>0) then
         deb= Tr3d_debTRICUB_WP
!$omp single
         Adz_post => Adz_post_3CWP
         Adz_flux => Adz_flux_3CWP
         do n=1, Tr3d_ntrTRICUB_WP
            Adz_stack(n)%src => tracers_P(deb+n-1)%pntr
            Adz_stack(n)%dst => tracers_M(deb+n-1)%pntr
         end do
!$omp end single
         call adz_post_tr_mono_hlt (1)
      end if

      if (Tr3d_ntrBICHQV_WP>0) then
         deb= Tr3d_debBICHQV_WP
!$omp single
         Adz_post => Adz_post_BQWP
         Adz_flux => Adz_flux_BQWP
         do n=1, Tr3d_ntrBICHQV_WP
            Adz_stack(n)%src => tracers_P(deb+n-1)%pntr
            Adz_stack(n)%dst => tracers_M(deb+n-1)%pntr
         end do
!$omp end single
         call adz_post_tr_mono_hlt (2)
      end if

      !Apply Bermejo-Conde mass-fixer for all tracers in Adz_bc
      !--------------------------------------------------------
      if (max(Tr3d_ntrTRICUB_WP,Tr3d_ntrBICHQV_WP)>0) call adz_post_tr_bc_hlt (0)
      call gtmg_stop (57)

      call gtmg_start (58, 'C_TR_ZLF0', 55)
      if (Tr3d_ntrTRICUB_WP>0 .and. Adz_BC_LAM_zlf_L) then
         deb= Tr3d_debTRICUB_WP
!$omp single
         do n=1, Tr3d_ntrTRICUB_WP
            Adz_stack(n)%dst => tracers_M(deb+n-1)%pntr
            Adz_stack(n)%pil => tracers_B(deb+n-1)%pntr
         end do
!$omp end single
         call adz_BC_LAM_zlf_0_hlt (Adz_stack,Tr3d_ntrTRICUB_WP,2)
      end if

      if (Tr3d_ntrBICHQV_WP>0 .and. Adz_BC_LAM_zlf_L) then
         deb= Tr3d_debBICHQV_WP
!$omp single
         do n=1, Tr3d_ntrBICHQV_WP
            Adz_stack(n)%dst => tracers_M(deb+n-1)%pntr
            Adz_stack(n)%pil => tracers_B(deb+n-1)%pntr
         end do
!$omp end single
         call adz_BC_LAM_zlf_0_hlt (Adz_stack,Tr3d_ntrBICHQV_WP,2)
      end if
      call gtmg_stop (58)

      if (Adz_verbose>0) call stat_mass_tracers_hlt (0,"AFTER ADVECTION")

      call gtmg_stop (55)
!
!     ---------------------------------------------------------------
!
      return
      end subroutine adz_tracers_massfixing
