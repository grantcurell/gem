module rootfind
  ! A set of functions provided to help with numerical root-finding
!!!#include <arch_specific.hf>
   implicit none
   private
#include <rmnlib_basics.hf>
#include <rmn/msg.h>


   ! Internal parameters
   integer, parameter :: LONG_CHAR=16                           !Long character string length

   ! Define API
   integer, parameter, public :: RF_OK=RMN_OK,RF_ERR=RMN_ERR    !Return statuses for functions
   public :: rf_nrbnd                                           !Bracketed Newton-Raphson technique

   interface rf_nrbnd
      module procedure rf_nrbnd_vec
      module procedure rf_nrbnd_scal
   end interface rf_nrbnd
   
contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  function rf_nrbnd_vec(F_xroot,F_fx,F_dfx,F_xlow,F_xhigh,F_tolerance,F_xfuzz,F_maxit) result(F_status)
    ! Use a combination of the Newton-Raphson and bisection algorithms to find
    ! the root of the provided function over the bracketing interval (F_xlow,F_xhigh)
    ! that is known to contain a root (i.e. F_fx(F_xlow) and F_fx(F_xhigh) have 
    ! opposite signs).  This is similar to the Brent-Dekker method, which guarantees
    ! convergence but does not make use of derivative information (it uses the secant
    ! technique instead of the Newton-Raphson component used here).
    implicit none

    ! Argument declaration
    real, dimension(:), intent(out) :: F_xroot    !Value of x for the root
    real, external :: F_fx                        !Scalar callback for function calculation
    real, external :: F_dfx                       !Scalar callback for derivative calculation
    real, dimension(:), intent(in) :: F_xlow      !Lower bound for root calculation
    real, dimension(:), intent(in) :: F_xhigh     !Upper bound for root calculation
    real, intent(in), optional :: F_tolerance     !Convergence criterion for root finding [0.001]
    real, intent(in), optional :: F_xfuzz         !Allow fractional departure from brackets [0.01]
    integer, intent(in), optional :: F_maxit      !Maximum number of iterations [100]
    integer :: F_status                           !Return status

    ! Local variables
    integer :: maxit,i,ni
    real :: tolerance,xfuzz,fxl0,fxh0

    ! Set error return status
    F_status = RF_ERR

    ! Set scope of arrays
    ni = size(F_xroot)

    ! Set default values
    tolerance = 0.001
    if (present(F_tolerance)) tolerance = F_tolerance
    xfuzz = 0.
    if (present(F_xfuzz)) xfuzz = F_xfuzz
    maxit = 100
    if (present(F_maxit)) maxit = F_maxit
    
    ! Loop over all points in the row
    ROW: do i=1,ni !#TODO: invert do i do while loops, or not since ni=1 in integrals

       fxl0 = F_fx(F_xlow(i))
       fxh0 = F_fx(F_xhigh(i))
       F_status = rf_nrbnd_scal(F_xroot(i),F_fx,F_dfx,F_xlow(i),F_xhigh(i),fxl0,fxh0,tolerance,xfuzz,maxit)
       if (F_status /= RF_OK) exit
       
    end do ROW

  end function rf_nrbnd_vec

  
  function rf_nrbnd_scal(F_xroot,F_fx,F_dfx,F_xlow,F_xhigh,F_fxl0,F_fxh0,F_tolerance,F_xfuzz,F_maxit) result(F_status)
    ! Use a combination of the Newton-Raphson and bisection algorithms to find
    ! the root of the provided function over the bracketing interval (F_xlow,F_xhigh)
    ! that is known to contain a root (i.e. F_fx(F_xlow) and F_fx(F_xhigh) have 
    ! opposite signs).  This is similar to the Brent-Dekker method, which guarantees
    ! convergence but does not make use of derivative information (it uses the secant
    ! technique instead of the Newton-Raphson component used here).
    implicit none

    ! Argument declaration
    real, intent(out) :: F_xroot    !Value of x for the root
    real, external :: F_fx                        !Scalar callback for function calculation
    real, external :: F_dfx                       !Scalar callback for derivative calculation
    real, intent(in) :: F_xlow      !Lower bound for root calculation
    real, intent(in) :: F_xhigh     !Upper bound for root calculation
    real, intent(in) :: F_fxl0,F_fxh0  !F_fx(F_xlow), F_fx(F_xhigh)
    real, intent(in), optional :: F_tolerance     !Convergence criterion for root finding [0.001]
    real, intent(in), optional :: F_xfuzz         !Allow fractional departure from brackets [0.01]
    integer, intent(in), optional :: F_maxit      !Maximum number of iterations [100]
    integer :: F_status                           !Return status

    ! Local variables
    integer :: maxit,iter
    real :: tolerance,xfuzz
    real :: xpt,xlow,xhigh,fxpt,dfxpt,dxold,dx,fxl,fxh

    ! Set error return status
    F_status = RF_ERR

    ! Set default values
    tolerance = 0.001
    if (present(F_tolerance)) tolerance = F_tolerance
    xfuzz = 0.
    if (present(F_xfuzz)) xfuzz = F_xfuzz
    maxit = 100
    if (present(F_maxit)) maxit = F_maxit
    
    ! Loop over all points in the row

    ! Set search direction
    fxl = F_fxl0
    if (fxl < 0.) then
       xlow = F_xlow
       xhigh = F_xhigh
       fxh = F_fxh0
    else
       xlow = F_xhigh
       xhigh = F_xlow
       fxh = fxl
       fxl = F_fxh0
    endif

    ! Confirm that a root lies between the given bracketing points, possibly allowing
    ! some tolerance for roots that lie almost precisely on a bracketing point (xfuzz)
    if (fxl*fxh > 0.) then
       dx = abs(xhigh-xlow)
       xlow = xlow - xfuzz*dx
       xhigh = xhigh + xfuzz*dx
#ifdef DEBUG
       if (F_fx(xlow)*F_fx(xhigh) > 0.) then

          call msg_toall(MSG_ERROR,'(rf_nrbnd) Bracketing interval (F_xlow,F_xhigh) has no root')
          return
       endif
#endif
    endif

    ! Set first guess values
    xpt = 0.5*(xlow+xhigh)
    dxold = abs(xhigh-xlow)
    dx = dxold
    fxpt  = F_fx(xpt)
    dfxpt = F_dfx(xpt)

    ! Loop to find root
    DOITER: do iter=1,maxit
       ! Determine optimal method for this step
       if ( ((xpt-xhigh)*dfxpt-fxpt) * ((xpt-xlow)*dfxpt-fxpt) > 0. .or. &
            abs(2.*fxpt) > abs(dxold*dfxpt) .or. dfxpt == 0. ) then
          ! Bisection method if Newton-Raphson is out of range or not converging
          dxold = dx
          dx = 0.5*(xhigh-xlow)
          xpt = xlow + dx
       else
          ! Continue with Newton-Raphson method
          dxold = dx
          dx = fxpt / dfxpt
          xpt = xpt - dx
       endif
       if (abs(dx) < tolerance) exit DOITER ! Convergence criterion has been met
       ! Set up for next iteration
       fxpt  = F_fx(xpt)
       dfxpt = F_dfx(xpt)
       if (fxpt < 0.) then
          xlow = xpt
       else
          xhigh = xpt
       endif
    enddo DOITER
    F_xroot = xpt

#ifdef DEBUG
    ! Check for algorithm failure
    if (iter >= maxit) then

       call msg_toall(MSG_ERROR,'(rf_nrbnd) Failed to find a root')
       return
    endif
#endif


    ! Successful completion
    F_status = RF_OK

  end function rf_nrbnd_scal

end module rootfind
