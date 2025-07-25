!-------------------------------------- LICENCE BEGIN -------------------------
!Environment Canada - Atmospheric Science and Technology License/Disclaimer,
!                     version 3; Last Modified: May 7, 2008.
!This is free but copyrighted software; you can use/redistribute/modify it under the terms
!of the Environment Canada - Atmospheric Science and Technology License/Disclaimer
!version 3 or (at your option) any later version that should be found at:
!http://collaboration.cmc.ec.gc.ca/science/rpn.comm/license.html

!This software is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
!without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
!See the above mentioned License/Disclaimer for more details.
!You should have received a copy of the License/Disclaimer along with this software;
!if not, you can write to: EC-RPN COMM Group, 2121 TransCanada, suite 500, Dorval (Quebec),
!CANADA, H9P 1J3; or send e-mail to service.rpn@ec.gc.ca
!-------------------------------------- LICENCE END ---------------------------

module vert_smooth
   implicit none
   private
   public :: vert_smooth1

contains

   
subroutine vert_smooth1(darr, levbot, ni, nig, nkm1, naz)
   use, intrinsic :: iso_fortran_env, only: REAL32
   use mo_gwspectrum, only: smco, rsum_wts, nsmax
   implicit none
!!!#include <arch_specific.hf>
#include <rmnlib_basics.hf>

   integer, intent(in) :: levbot, ni, nig, nkm1, naz
   real(REAL32), intent(inout) :: darr(ni,naz,nkm1)

   !@Author
   !  aug. 3/95 - c. mclandress
   !@Object
   !  Smooth a longitude by altitude array in the vertical over a
   !  specified number of levels using a three point smoother.
   !@Arguments
   !  note: input array darr is modified on output
   !          - Output/Input -
   ! darr     smoothed array (on output),unsmoothed array of data (on input)
   !          - Input
   ! darr     unsmoothed array of data (on input).
   ! smco     smoothing coefficient for a 1:coeff:1 stencil.
   !          (e.g., coeff = 2 will result in a smoother which
   !          weights the level l gridpoint by two and the two
   !          adjecent levels (l+1 and l-1) by one).
   ! nsmax    number of times to smooth in vertical.
   !          (e.g., nsmooth=1 means smoothed only once,
   !          nsmooth=2 means smoothing repeated twice, etc.)
   ! levbot   last altitude level to use (lev1 < levbot <= nkm1).
   ! ni       number of longitudes.
   ! nig      horizontal operator scope
   ! nkm1     number of vertical levels.

   !  internal variables.

   integer :: i, l, nz, ns
   real(REAL32) :: work(ni,naz,nkm1)
   !-----------------------------------------------------------------------

   !  smooth nsmax times

   do ns = 1,nsmax

      !  copy darr into work array.
      do l = 1,levbot
         do nz = 1,naz
            do i = 1,nig
               work(i,nz,l) = darr(i,nz,l)
            end do
         end do
      end do

      !  smooth array work in vertical direction and put into darr.
      do l = 2,levbot-1
         do nz = 1,naz
            do i = 1,nig
               darr(i,nz,l) = (work(i,nz,l+1) + smco*work(i,nz,l) + work(i,nz,l-1)) * rsum_wts
            end do
         end do
      end do
   end do

   return
   !-----------------------------------------------------------------------
end subroutine vert_smooth1

end module vert_smooth
