!-------------------------------------- LICENCE BEGIN ------------------------------------
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
!-------------------------------------- LICENCE END --------------------------------------
!**S/P TLINE3 - OPTICAL DEPTH FOR THREE MIXED GASES

module ccc2_tline3z_m
   implicit none
   private
   public :: ccc2_tline3z
   
contains
   
      subroutine ccc2_tline3z(taug, coef1, coef2, &
                         coef3, s1, s2, s3, dp, dip, dt, inpt, &
                         lev1, gh, lc, nig, ni, lay)
      implicit none
!!!#include <arch_specific.hf>

      integer, intent(in) :: ni, lay, lc, lev1, nig
      real, intent(inout) :: taug(ni,lay)
      real, intent(in) :: coef1(5,lc), coef2(5,lc), coef3(5,lc), &
           s1(ni,lay), s2(ni,lay), s3(ni,lay), dp(ni,lay), &
           dip(ni,lay), dt(ni,lay)
      integer, intent(in) :: inpt(ni,lay)
      logical, intent(in) :: gh

!Authors
!
!        J. Li, M. Lazare, CCCMA, rt code for gcm4
!        (Ref: J. Li, H. W. Barker, 2005:
!        JAS Vol. 62, no. 2, pp. 286\226309)
!        P. Vaillancourt, D. Talbot, RPN/CMC;
!        adapted for CMC/RPN physics (May 2006)
!
!Revisions
!
! 001   M. Lazare (May 05,2006)- previous version tline3x for gcm15e:
!                              - implement rpn fix for inpt.
! 002   M. Lazare   (Apr 18,2008) - previous version tline3y for gcm15g:
!                               - cosmetic change of n->lc passed
!                                 in and used in dimension of coef
!                                 array(s), so that it is not redefined
!                                 and passed back out to calling
!                                 routine, changing value in data
!                                 statement!
!                               - add threadprivate for common block
!                                 "trace", in support of "radforce"
!                                 model option. this requires a new
!                                 version so that gcm15f remains
!                                 undisturbed.
! 003    M.Lazarre,K.Winger   (Apr 08) - correct bug - lc now used for dimension of array and n as a variable integer
! 004   J. Li    (feb 09,2009) -  new version for gcm15h:
!                               - 3d ghg implemented, thus no need
!                                 for "trace" common block or
!                                 temporary work arrays to hold
!                                 mixing ratios of ghg depending on
!                                 a passed, specified option.
! 005  P. vaillancourt, A-M. Leduc (Apr 2010) - Integrating the Li/Lazare 2009 version.(tline3z)
!                                  replace ng2, ng3 by s2, s3
!
!Object
!
!     The same as tlinel, but with three mixed gases. one with varying
!     mixing ratio the other two with constant mixing ratio
!
!     taug: gaseous optical depth
!     s1:   input h2o mixing ratio for each layer
!     dp:   air mass path for a model layer (explained in raddriv).
!     dip:  interpolation factor for pressure between two neighboring
!           standard input data pressure levels
!     dt:   layer temperature - 250 k
!     inpt: number of the level for the standard input data pressures
!
!Implicites
!
#include "ccc_tracegases.cdk"

      integer :: k, i, m, n, lay1
      real :: x1, y1, x2, y2, z1, z2

   lay1 = lev1
   if (gh) lay1 = 1

   DO_K: do k = lay1, lay
      F_950: if (inpt(1,k) < 950) then

         DO_I1: do i = 1, nig
            m  =  inpt(i,k)
            n  =  m + 1
            x2        =  coef1(1,n) + dt(i,k) * (coef1(2,n) + dt(i,k) * &
                 (coef1(3,n) + dt(i,k) * (coef1(4,n) + &
                 dt(i,k) * coef1(5,n))))
            y2        =  coef2(1,n) + dt(i,k) * (coef2(2,n) + dt(i,k) * &
                 (coef2(3,n) + dt(i,k) * (coef2(4,n) + &
                 dt(i,k) * coef2(5,n))))
            z2        =  coef3(1,n) + dt(i,k) * (coef3(2,n) + dt(i,k) * &
                 (coef3(3,n) + dt(i,k) * (coef3(4,n) + &
                 dt(i,k) * coef3(5,n))))
            IF_M0A: if (m > 0) then
               x1      =  coef1(1,m) + dt(i,k) * (coef1(2,m) + dt(i,k) * &
                    (coef1(3,m) + dt(i,k) * (coef1(4,m) + &
                    dt(i,k) * coef1(5,m))))
               y1      =  coef2(1,m) + dt(i,k) * (coef2(2,m) + dt(i,k) * &
                    (coef2(3,m) + dt(i,k) * (coef2(4,m) + &
                    dt(i,k) * coef2(5,m))))
               z1      =  coef3(1,m) + dt(i,k) * (coef3(2,m) + dt(i,k) * &
                    (coef3(3,m) + dt(i,k) * (coef3(4,m) + &
                    dt(i,k) * coef3(5,m))))
               taug(i,k) = ( (x1 + (x2 - x1) * dip(i,k)) * s1(i,k) + &
                    (y1 + (y2 - y1) * dip(i,k)) * s2(i,k) + &
                    (z1 + (z2 - z1) * dip(i,k)) * s3(i,k)  ) * &
                    dp(i,k)
            else
               taug(i,k) = dp(i,k) * ( &
                    x2 * dip(i,k) * s1(i,k) + &
                    y2 * dip(i,k) * s2(i,k) + &
                    z2 * dip(i,k) * s3(i,k) )
            endif IF_M0A
         enddo DO_I1

      else  !IF_950

         m  =  inpt(1,k) - 1000
         n  =  m + 1
         IF_M0B: if (m > 0) then

            DO_I2: do i = 1, nig
               x2        =  coef1(1,n) + dt(i,k) * (coef1(2,n) + dt(i,k) * &
                    (coef1(3,n) + dt(i,k) * (coef1(4,n) + &
                    dt(i,k) * coef1(5,n))))
               y2        =  coef2(1,n) + dt(i,k) * (coef2(2,n) + dt(i,k) * &
                    (coef2(3,n) + dt(i,k) * (coef2(4,n) + &
                    dt(i,k) * coef2(5,n))))
               z2        =  coef3(1,n) + dt(i,k) * (coef3(2,n) + dt(i,k) * &
                    (coef3(3,n) + dt(i,k) * (coef3(4,n) + &
                    dt(i,k) * coef3(5,n))))
               x1      =  coef1(1,m) + dt(i,k) * (coef1(2,m) + dt(i,k) * &
                    (coef1(3,m) + dt(i,k) * (coef1(4,m) + &
                    dt(i,k) * coef1(5,m))))
               y1      =  coef2(1,m) + dt(i,k) * (coef2(2,m) + dt(i,k) * &
                    (coef2(3,m) + dt(i,k) * (coef2(4,m) + &
                    dt(i,k) * coef2(5,m))))
               z1      =  coef3(1,m) + dt(i,k) * (coef3(2,m) + dt(i,k) * &
                    (coef3(3,m) + dt(i,k) * (coef3(4,m) + &
                    dt(i,k) * coef3(5,m))))
               taug(i,k) = ( (x1 + (x2 - x1) * dip(i,k)) * s1(i,k) + &
                    (y1 + (y2 - y1) * dip(i,k)) * s2(i,k) + &
                    (z1 + (z2 - z1) * dip(i,k)) * s3(i,k) ) * &
                    dp(i,k)
            enddo DO_I2

         else  !IF_M0b

            DO_I3: do i = 1, nig
               x2        =  coef1(1,n) + dt(i,k) * (coef1(2,n) + dt(i,k) * &
                    (coef1(3,n) + dt(i,k) * (coef1(4,n) + &
                    dt(i,k) * coef1(5,n))))
               y2        =  coef2(1,n) + dt(i,k) * (coef2(2,n) + dt(i,k) * &
                    (coef2(3,n) + dt(i,k) * (coef2(4,n) + &
                    dt(i,k) * coef2(5,n))))
               z2        =  coef3(1,n) + dt(i,k) * (coef3(2,n) + dt(i,k) * &
                    (coef3(3,n) + dt(i,k) * (coef3(4,n) + &
                    dt(i,k) * coef3(5,n))))
               taug(i,k) = dp(i,k) * ( &
                    x2 * dip(i,k) * s1(i,k) + &
                    y2 * dip(i,k) * s2(i,k) + &
                    z2 * dip(i,k) * s3(i,k) )
            enddo DO_I3

         endif IF_M0b

      endif F_950
   enddo DO_K
   
   return
end subroutine ccc2_tline3z

end module ccc2_tline3z_m
