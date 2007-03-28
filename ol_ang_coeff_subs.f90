! -*- mode: F90; mode: font-lock; column-number-mode: true; vc-back-end: CVS -*-
! ------------------------------------------------------------------------------
! $Id: ol_ang_coeff_subs.f90,v 1.11 2005/10/21 12:24:12 drb Exp $
! ------------------------------------------------------------------------------
! Module angular_coeff_routines
! ------------------------------------------------------------------------------
! Code area 11: basis functions
! ------------------------------------------------------------------------------

!!****h* Conquest/angular_coeff_routines
!!  NAME
!!   angular_coeff_routines
!!  PURPOSE
!!   Holds routines to calculate angular coefficients relevant to 
!!   evaluation of the radial tables.
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!   2005/07/11 dave
!!    changed inout specification to in for ifort compilation
!!   2007/01/05 17:30 dave
!!    included prefac and fact arrays
!!  SOURCE
!!

module angular_coeff_routines

  use datatypes
  use bessel_integrals, ONLY: fact, lmax_fact

  implicit none

  ! -------------------------------------------------------
  ! RCS ident string for object file id
  ! -------------------------------------------------------
  character(len=80), private :: RCSid = "$Id: ol_ang_coeff_subs.f90,v 1.11 2005/10/21 12:24:12 drb Exp $"

  integer,parameter :: lmax_prefac=8
  real(double) :: prefac(-1:lmax_prefac,-lmax_prefac:lmax_prefac)
  real(double) :: prefac_real(-1:lmax_prefac,-lmax_prefac:lmax_prefac)

!!***

contains

!!****f* angular_coeff_routines/calc_index_new *
!!
!!  NAME 
!!   calc_index_new
!!  USAGE
!!   calc_index_new(l1,l2,l3,m1,m2,m3,l_index,m_index)
!!  PURPOSE
!!   calculates position of angular coefficient corresponding to the
!!   l1,l2,l3,m1,m2 input, within the coefficients array (see ol_int_datatypes) 
!!  INPUTS
!!   l1, l2, l3 orbital angular momenta triplet
!!   m1,m2 azimuthal values of a.m .associated with first two orbital angular momenta
!!  USES
!!   none
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine calc_index_new(l1,l2,l3,m1,m2,m3,l_index,m_index)

    implicit none

    integer, intent(in) ::  l1,l2,l3,m1,m2,m3
    integer, intent(out) :: l_index,m_index
    integer :: i,j,k,l1_dum,l2_dum,m1_dum,m2_dum
    
    !taking care of case where l2>l1;
    if(l2.gt.l1) then !switching so largest l comes first in indexing scheme
       l1_dum = l2
       m1_dum = m2
       l2_dum = l1
       m2_dum = m1
    else  !no switching necessary
       !write(*,*) 'l1 greater or equal to l2'
       l1_dum = l1
       m1_dum = m1
       l2_dum = l2
       m2_dum = m2
    endif
       
    !work out l_index, position of l-triplet in
    !coefficients array
    l_index=1
    if(l1_dum>0) then
       do i=0,l1_dum-1
          l_index = l_index + (i+1)*(i+2)/2
       enddo
    end if
    if(l2_dum>0) then
       do i=0,l2_dum-1
          l_index = l_index + (i+1)
       enddo
    end if
    l_index = l_index + (l3 - (l1_dum-l2_dum))/2

    !also working out position of m_triplet within m_combs array
    !write(*,*) l1_dum,m1_dum,l2_dum,m2_dum
    m_index = 1
    m_index = m_index + (2*l1_dum+1)*(m2_dum+l2_dum)
    m_index = m_index + (m1_dum+l1_dum)

  end subroutine calc_index_new
!!***
  
!!****f* angular_coeff_routines/calc_mat_elem *
!!
!!  NAME 
!!   calc_mat_elem
!!  USAGE
!!   calc_mat_elem(sp1,l1,nz1,m1,sp2,l2,nz2,m2,dx,dy,dz,mat_val)
!!
!!  PURPOSE
!!   combines radial tables and angular coefficients to produce overlap integral
!!   matrix element
!!  INPUTS
!!   sp1,sp2 indices of species  
!!   dx,dy,dz Cartesian displacement between PAO's
!!   l1,nz1,m1,l2,nz2,m2 relevant PAO angular momenta details
!!   mat_val ; overlap matrix element
!!  USES
!!   ol_int_datatypes, datatypes, cubic_spline_routines, make_rad_tables   
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine calc_mat_elem_gen(case,sp1,l1,nz1,m1,sp2,l2,nz2,m2,dx,dy,dz,mat_val)

    use datatypes
    use ol_int_datatypes !,ONLY : rad_tables,rad_tables_ke,rad_tables_nlpf_pao,ol_index&
    !&,ol_index_nlpf_pao
    use cubic_spline_routines, ONLY: spline_ol_intval_new2
    use GenComms, ONLY: inode, ionode, myid !for debugging purposes
!    use make_rad_tables, ONLY: get_max_paoparams

    implicit none

    !routine to evaluate overlap matrix elements for the following cases
    !1 - pao_pao, 2 - pao_ke_pao, 3 - nlpf_pao (specified by case).
    integer, intent(in) :: case,sp1,l1,nz1,m1,sp2,l2,nz2,m2
    integer count,n_lvals,lmax,nzmax,npts,i,l3
    real(double), intent(in) :: dx,dy,dz
    real(double), intent(out) :: mat_val
    real(double) :: r, theta, phi, ang_factor, del_x, ind_val
    !real(double), allocatable, dimension(:) :: radial_table
    
    !find required set of radial tables through indices
    if(case.lt.3) then !either case 1 or 2
       count = ol_index(sp1,sp2,nz1,nz2,l1,l2)
       n_lvals = rad_tables(count)%no_of_lvals
       npts = rad_tables(count)%rad_tbls(1)%npnts
    else
       count = ol_index_nlpf_pao(sp1,sp2,nz1,nz2,l1,l2)
       !write(48+myid,*) l1,l2,count
       n_lvals = rad_tables_nlpf_pao(count)%no_of_lvals
       npts = rad_tables_nlpf_pao(count)%rad_tbls(1)%npnts
    endif
    
    call convert_basis(dx,dy,dz,r,theta,phi)
    
    mat_val = 0.0_double ; ind_val = 0.0_double
    if(case.lt.3) then
       del_x = rad_tables(count)%rad_tbls(1)%del_x
       do i = 1,n_lvals
          l3 = rad_tables(count)%l_values(i)
          call ol_ang_factor_new(l1,l2,l3,m1,m2,theta,phi,ang_factor)
          !multiply radial table(l3) by the associated angular factor
          if(case.eq.1) then
             call spline_ol_intval_new2(r,rad_tables(count)%rad_tbls(i)%&
                  &arr_vals(1:npts),rad_tables(count)%rad_tbls(i)%&
                  &arr_vals2(1:npts),npts,del_x,ind_val)
             mat_val = mat_val + ind_val*ang_factor
          else !case must eq 2
             call spline_ol_intval_new2(r,rad_tables_ke(count)%rad_tbls(i)%&
                  &arr_vals(1:npts),rad_tables_ke(count)%rad_tbls(i)%&
                  &arr_vals2(1:npts),npts,del_x,ind_val)
             mat_val = mat_val + ind_val*ang_factor
          endif
       enddo
    else
       del_x = rad_tables_nlpf_pao(count)%rad_tbls(1)%del_x
       do i = 1,n_lvals
          l3 = rad_tables_nlpf_pao(count)%l_values(i)
          call ol_ang_factor_new(l1,l2,l3,m1,m2,theta,phi,ang_factor)
          !multiply radial table(l3) by the associated angular factor
          call spline_ol_intval_new2(r,rad_tables_nlpf_pao(count)%rad_tbls(i)%&
               &arr_vals(1:npts),rad_tables_nlpf_pao(count)%rad_tbls(i)%&
               &arr_vals2(1:npts),npts,del_x,ind_val)
          mat_val = mat_val + ind_val*ang_factor
       enddo
    endif
    
  end subroutine calc_mat_elem_gen
!!***  

!!****f* angular_coeff_routines/ol_ang_factor_new *
!!
!!  NAME 
!!   ol_ang_factor_new
!!  USAGE
!! 
!!  PURPOSE
!! 
!!  INPUTS
!!   l1,l2,l3 - three values of orbital angular momentum
!!   m1,m2 azimuthal values associated with the first two values of orbital angular momentum.
!!  USES
!!   ol_int_datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine ol_ang_factor_new(l1,l2,l3,m1,m2,theta,phi,ang_factor)
    
    use ol_int_datatypes !,ONLY : coefficients
    use datatypes

    implicit none
    !routine to calculate angular factors for radial tables
    integer, intent(in) :: l1,l2,l3,m1,m2
    integer m3,l_index,m_index,ma,mc,m1_dum,m2_dum
    real(double), intent(in) :: theta, phi
    real(double), intent(out) :: ang_factor
    real(double) :: ang_coeff1,ang_coeff2,ang_factor1,ang_factor2,af1,af2
    
    ang_coeff1 = 0.0_double
    ang_coeff2 = 0.0_double
    ang_factor1 = 0.0_double
    ang_factor2 = 0.0_double
    
    !component 2
    ma = m1-m2
    call calc_index_new(l1,l2,l3,-m1,m2,ma,l_index,m_index)
    ang_coeff2 = coefficients(l_index)%m_combs(m_index)
    if(m1.ge.0.and.m2.ge.0) then
       ang_factor2 = ((-1)**m2)*prefac(l3,-ma)*assoclegpol(l3,-ma,theta)&
            &*cos(-ma*phi)*2.0_double
       if(m1.gt.0.and.m2.gt.0) then
          ang_factor2 = ang_factor2*(1.0_double/2.0_double)
       else if(m1.eq.0.and.m2.eq.0) then
          ang_factor2 = ang_factor2*(1.0_double/4.0_double)
       else !bit of both..
          ang_factor2 = ang_factor2*(1.0_double/(2.0_double*sqrt(2.0_double)))
       endif
       
    else if(m1.lt.0.and.m2.lt.0) then
       ang_factor2 = ((-1)**m1)*prefac(l3,ma)*assoclegpol(l3,ma,theta)&
            &*cos(ma*phi)*2.0_double*(1.0_double/2.0_double)
       
    else !m1lt0 and m2>=0 or vice versa
       !make sure m1 is .ge.0, m2.lt.0
       if(m1.ge.0) then
          m1_dum = m1
          m2_dum = m2
       else
          m1_dum = m2
          m2_dum = m1
          ma = m1_dum-m2_dum
       endif
       
       ang_factor2 = ((-1)**m1_dum)*prefac(l3,ma)*assoclegpol(l3,ma,theta)&
            &*sin(-ma*phi)*2.0_double!*(1.0_double/2.0_double)
       if(m1_dum.gt.0) then !m2 must be .lt.0
          ang_factor2 = ang_factor2*(1.0_double/2.0_double)
       else if(m1_dum.eq.0) then
          ang_factor2 = ang_factor2*(1.0_double/(2.0_double*sqrt(2.0_double)))
       else if(m2_dum.gt.0) then !m1 must be .lt. 0
          ang_factor2 = ang_factor2*(1.0_double/2.0_double)
       else !m2.eq.0 and m1.lt.0
          ang_factor2 = ang_factor2*(1.0_double/(2.0_double*sqrt(2.0_double)))
       endif
       
    endif
    
    !component 1
    mc = -(m1+m2)
    call calc_index_new(l1,l2,l3,m1,m2,mc,l_index,m_index)
    ang_coeff1 = coefficients(l_index)%m_combs(m_index)
    if(m1.ge.0.and.m2.ge.0) then
       ang_factor1 = prefac(l3,mc)*assoclegpol(l3,mc,theta)&
            &*cos(mc*phi)*2.0_double
       if(m1.gt.0.and.m2.gt.0) then
          ang_factor1 = ang_factor1*(1.0_double/2.0_double)
       else if(m1.eq.0.and.m2.eq.0) then
          ang_factor1 = ang_factor1*(1.0_double/4.0_double)
       else
          !write(*,*) 'mi.gt.0, mj.eq.0'
          !write(*,*) 'ang factor 1', ang_factor1
          ang_factor1 = ang_factor1*(1.0_double/(2.0_double*sqrt(2.0_double)))
       endif
    else if(m1.lt.0.and.m2.lt.0) then
       ang_factor1 = prefac(l3,mc)*assoclegpol(l3,mc,theta)&
            &*cos(mc*phi)*2.0_double*(-1.0_double/2.0_double)
    else !m1lt0 and m2>0 or vice versa
       !make sure m1 is .ge.0, m2.lt.0
       if(m1.ge.0) then
          m1_dum = m1
          m2_dum = m2
       else
          m1_dum = m2
          m2_dum = m1 !mc remains unchanged..
       endif
       
       ang_factor1 = ((-1)**mc)*prefac(l3,-mc)*assoclegpol(l3,-mc,theta)&
            &*sin(-mc*phi)*2.0_double
       if(m1_dum.gt.0) then !m2 must be .lt.0
          ang_factor1 = ang_factor1*(1.0_double/2.0_double)
       else if(m1_dum.eq.0) then !m2 must be .lt.0
          ang_factor1 = ang_factor1*(1.0_double/(2.0_double*sqrt(2.0_double)))
       else if(m2_dum.gt.0) then !m1 must be .lt.0 
          ang_factor1 = ang_factor1*(-1.0_double/2.0_double)
       else !m2.eq.0 and m1.lt.0
          !write(*,*) 'm2.eq.0 m1.lt.0'
          ang_factor1 = ang_factor1*(1.0_double/(2.0_double*sqrt(2.0_double)))
       endif
          
    endif
    !now calculating real spherical harmonic prefactors depending on which 
    !m1, m2 values we have
    af1 = ang_coeff1*ang_factor1
    af2 = ang_coeff2*ang_factor2
    ang_factor = (af1+af2)*8.0_double
  end subroutine ol_ang_factor_new
!!***  

!!****f* angular_coeff_routines/make_ang_coeffs *
!!
!!  NAME 
!!   make_ang_coeffs
!!  USAGE
!!   make_ang_coeffs
!!  PURPOSE
!!   generates vector-coupling  products (Clebsch Gordon products)
!!   that give value of integral of triple spherical harmonics
!!  INPUTS
!!   paos in pao_format
!! 
!!  USES
!!   ol_int_datatypes, pao_format, make_rad_tables, ONLY : get_max_paoparams
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine make_ang_coeffs

    use datatypes
    use ol_int_datatypes !, ONLY : coefficients
    use make_rad_tables, ONLY : get_max_pao_nlpfparams

    implicit none

    !code to calculate and list the integrals
    !of triple spherical harmonics
    integer :: l1,l2,l3,m1,m2,m3,lmax,i,j,n_elements_l,tot_l_trips
    integer :: tot,no_m_combs,ncount,m_combo,l,m,n,k,mtot,nzmax
    real(double) :: int_val,coeff,index
        
    call get_max_pao_nlpfparams(lmax,nzmax)
    !allocating array to hold angular coefficients information..
    call get_ang_coeffparams(lmax,tot_l_trips) !size for coefficients array
    allocate(coefficients(tot_l_trips))
    !now calculate and store angular coefficients
    ncount=1
    do l1=0,lmax
       do l2=0,l1
          do l3=abs(l1-l2),abs(l1+l2),2
             !need to be careful with storage order of m
             !combinations
             !number of n_combinations is;
             no_m_combs = ((2*l2)+1)*((2*l1)+1)
             if(ncount>tot_l_trips) write(*,*) 'ERROR ! Coefficients overrun: ',ncount,tot_l_trips
             coefficients(ncount)%n_m_combs=no_m_combs
             
             allocate(coefficients(ncount)%m_combs(no_m_combs))
             m_combo=1
             do m2=-l2,l2
                do m1=-l1,l1
                   m3=-(m1+m2)
                   if(abs(m3).gt.l3) then
                      coeff=0.0
                   else
                      call sph_hrmnc_tripint(l1,l2,l3,m1,m2,m3,int_val)
                      
                      coeff = int_val
                   endif
                   coefficients(ncount)%m_combs(m_combo) = coeff
                   m_combo = m_combo+1
                enddo
             enddo
             ncount=ncount+1
          enddo
       enddo
    enddo
    ncount = ncount-1 !size of coefficients array to be passed
  end subroutine make_ang_coeffs
!!***

!!****f* angular_coeff_routines/get_ang_coeffparams *
!!
!!  NAME 
!!   get_ang_coeffparams
!!  USAGE
!!   get_ang_coeffparams(lmax,tot_l_trips)
!!  PURPOSE
!!   calculates size of coefficients (storage) array based on maximum
!!   angular momentum of paos.  
!!  INPUTS
!!   lmax - maximum angular momentum
!!   tot_l_trips - size of coefficients array
!!  USES
!!   ol_int_datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine get_ang_coeffparams(lmax,tot_l_trips)

    implicit none

    integer, intent(out) :: tot_l_trips
    integer, intent(in) :: lmax
    integer :: l,i,n_elements_l

    !initialising n_elements_l value to nought
    tot_l_trips = 0
    n_elements_l = 0
    do i = 0,lmax
       n_elements_l = (i+1)*(i+2)/2
       tot_l_trips = tot_l_trips + n_elements_l
    enddo

  end subroutine get_ang_coeffparams
!!***

!!****f* angular_coeff_routines/vect_coupl *
!!
!!  NAME 
!!   vect_coupl
!!  USAGE
!!   vect_coupl(j1,j2,j3,m1,m2,s_coup)
!!  PURPOSE
!!   Calculate Clebsch-Gordon (vector coupling) coefficients
!!  INPUTS
!!   j1,j2,j3,m1,m2 angular momentum values.
!! 
!!  USES
!!   none
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine vect_coupl(j1,j2,j3,m1,m2,s_coup)
    use datatypes
    implicit none
    ! subroutine to evaluate the vector coupling coefficients.
    integer, intent(in) :: j1,j2,j3,m1,m2
    integer max_x,min_x,x
    integer :: k1,k2,k3,n1,n2,n3
    real(double), intent(out) :: s_coup
    !   real, external :: fact
    real(double) :: s_coup1,s_coup2,s_coup3

    s_coup1 = 0.0_double
    s_coup2 = 0.0_double
    s_coup3 = 0.0_double
    
    s_coup1 = fact(j3+j1-j2)*fact(j3-j1+j2)*fact(j1+j2-j3)*fact(j3+m1+m2) *fact(j3-m1-m2)

    s_coup2 = fact(j3+j2+j1+1)*fact(j1-m1)*fact(j1+m1)*fact(j2-m2) *fact(j2+m2)

    if(j2-j1+m1+m2.gt.0) then
       min_x = j2-j1+m1+m2
    else
       min_x = 0
    endif

    if(j3+m1+m2.gt.j3-j1+j2) then
       max_x = j3-j1+j2
    else
       max_x = j3+m1+m2
    endif
    do x = min_x,max_x
       s_coup3 = s_coup3 + ((-1)**(x+j2+m2))*(sqrt(((2.0_double*j3)+1.0_double))&
            &*fact(j3+j2+m1-x)*fact(j1-m1+x))/&
            &(fact(j3-j1+j2-x)*fact(j3+m1+m2-x)*fact(x)&
            &*fact(x+j1-j2-m1-m2))
    enddo

    s_coup = sqrt(s_coup1/s_coup2)*s_coup3
   
  end subroutine vect_coupl
!!***

!!****f* angular_coeff_routines/wigner_3j *
!!
!!  NAME 
!!   wigner_3j
!!  USAGE
!!   wigner_3j(j1,j2,j3,m1,m2,m3,wig_3j)
!!  PURPOSE
!!   Calculate Wigner 3-j symbol (product of vector-coupling coefficients)
!!  INPUTS
!!   j1,j2,j3,m1,m2 - angular momentum values
!!   wig_3j - value of 3-j symbol
!!  USES
!!   none
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine wigner_3j(j1,j2,j3,m1,m2,m3,wig_3j)
    use datatypes
    implicit none

    ! evaluating Wigner 3-j symbols
    integer, intent(in) :: j1,j2,j3,m1,m2,m3
    real(double), intent(out) :: wig_3j
    real(double) :: s_coup
    real(double), parameter :: pi=3.1415926535897932_double
    if(m1+m2+m3.eq.0) then
       call vect_coupl(j1,j2,j3,m1,m2,s_coup)
       wig_3j= ((-1)**(j1-j2-m3))*s_coup/(sqrt(2.0*j3+1))
    else
       wig_3j=0.0_double
    endif

  end subroutine wigner_3j
!!***

!!****f* angular_coeff_routines/sph_hrmnc_tripint *
!!
!!  NAME 
!!   sph_hrmnc_tripint
!!  USAGE
!!   sph_hrmnc_tripint(j1,j2,j3,m1,m2,m3,intgrlval)
!!  PURPOSE
!!   Calculate integral of triplet of spherical harmonics
!!  INPUTS
!!   j1,j2,j3,m1,m2 - angular momentum values.
!!   intgrlval - value of integral
!!  USES
!!   none
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine sph_hrmnc_tripint(j1,j2,j3,m1,m2,m3,intgrlval)
    use datatypes
    implicit none
    ! 23/04/03 R Choudhury
    ! subroutine to evaluate integral over solid angle of 
    ! spherical harmonic triple product.
    ! This version of the code seems to be fully functional..
    integer, intent(in) :: j1,j2,j3,m1,m2,m3
    real :: l1,l2,l3,z1,z2,z3 
    real(double) :: wig_3j,s_coup,pref,wig_3ja,wig_3jb,m1neg
    real(double), intent(out) :: intgrlval
    real(double), parameter :: pi = 3.1415926535897932_double
    integer i
    wig_3j = 0.0_double   !initialising all values to zero
    wig_3ja = 0.0_double
    wig_3jb = 0.0_double
    pref = 0.0_double
    s_coup = 0.0_double
    !taking complex conjugate of spherical harmonic l1,m1
    
    call wigner_3j(j1,j2,j3,m1,m2,m3,wig_3j) ! calculate 3j symbols
    wig_3ja = wig_3j
    wig_3j = 0.0_double
    call wigner_3j(j1,j2,j3,0,0,0,wig_3j)
    wig_3jb = wig_3j
    wig_3j = 0.0_double
    
    pref = sqrt(((2.0_double*j1)+1)*((2.0_double*j2)+1)&
         *((2.0_double*j3)+1)/(4.0_double*pi))
    intgrlval = pref*wig_3ja*wig_3jb

  end subroutine sph_hrmnc_tripint
  !!***
  
!!****f* angular_coeff_routines/convert_basis *
!!
!!  NAME 
!!   convert_basis
!!  USAGE
!!   convert_basis(x,y,z,r,thet,phi)
!!  PURPOSE
!!   Converts a displacement given in Cartesian coords
!!   to spherical polar coords.
!!  INPUTS
!!   x, y, z Cartesian components of displacement vector 
!!   r, thet, phi - spherical polar components of displacement vector
!!  USES
!!   datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!   13:16, 21/10/2005 drb 
!!    Removed potential divide by zero (thanks to Andy Gormanly)
!!  SOURCE
!!

  subroutine convert_basis(x,y,z,r,thet,phi)
    use datatypes
    use numbers, ONLY: pi, half, very_small, three_halves, zero
    implicit none
    !routine to convert Cartesian displacements into displacements
    !in spherical polar coordinates
    real(double), intent(in) :: x,y,z
    real(double), intent(inout) :: r,thet,phi
    real(double) :: x2,y2,z2,mod_r,mod_r_plane,num

    x2 = x*x
    y2 = y*y
    z2 = z*z
    mod_r = sqrt(x2+y2+z2)
    mod_r_plane = sqrt(x2+y2)
    if(mod_r<very_small) then
       r = zero
       thet = zero
       phi = zero
       return
    end if

    if(abs(z)<very_small) then
       thet = half*pi
    else
       thet = acos(z/mod_r) !need to make sure this ratio doesn't disappear as well..
    endif

    if(abs(x2)<very_small.and.abs(y2)<very_small) then
       phi = zero
    else
       if(x<zero) then
          if(y<zero) then
             !3rd quadrant
             phi = pi+acos(-x/mod_r_plane)
          else 
             !2nd quadrant
             phi = (half*pi)+acos(y/mod_r_plane)
          endif
       else
          if(y<zero) then
             !4th quadrant
             phi = (three_halves*pi)+acos(-y/mod_r_plane)
          else
             !1st quadrant
             phi = acos(x/mod_r_plane)
          endif
       endif
    endif
   
    r = mod_r

  end subroutine convert_basis
  !!***

!!****f* angular_coeff_routines/evaluate_pao *
!!
!!  NAME 
!!   evaluate_pao
!!  USAGE
!!   evaluate_pao(sp,l,nz,m,x,y,z,pao_val)
!!  PURPOSE
!!   Returns value of specified PAO at given point in space
!!  INPUTS
!!   x, y, z Cartesian components of displacement vector 
!!   sp,l,nz,m - species no., l ang momentum value, zeta value
!!   and azimuthal quantum number of specified pao
!!  USES
!!   datatypes, pao_format, cubic_spline_routines
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   25/09/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!

  subroutine evaluate_pao(sp,l,nz,m,x,y,z,pao_val)
    use datatypes
    use pao_format !,ONLY : pao
    use cubic_spline_routines !,ONLY : spline_ol_intval_new2
    implicit none
    !routine to return value of PAO at given point in space
    integer, intent(in) :: sp,l,nz,m
    real(double), intent(in) :: x,y,z
    real(double), intent(out) :: pao_val
    real(double) :: r,theta,phi,del_r,y_val,val
    integer :: npts
    
    !convert Cartesians into spherical polars
    call convert_basis(x,y,z,r,theta,phi)
    !interpolate for required value of radial function
    npts = pao(sp)%angmom(l)%zeta(nz)%length
    del_r = (pao(sp)%angmom(l)%zeta(nz)%cutoff/&
         &(pao(sp)%angmom(l)%zeta(nz)%length-1))
    
    call spline_ol_intval_new2(r,pao(sp)%angmom(l)%zeta(nz)%table, &
         pao(sp)%angmom(l)%zeta(nz)%table2,npts,del_r,pao_val)
    !now multiply by value of spherical harmonic
    y_val = re_sph_hrmnc(l,m,theta,phi)
    
    pao_val = pao_val*y_val
    ! Scale by r**l to remove Siesta normalisation
    if(l==1) then ! p
       pao_val = pao_val*r
    else if(l==2) then ! d
       pao_val = pao_val*r*r
    else if(l==3) then ! f
       pao_val = pao_val*r*r*r
    else if(l>3) then
       write(*,*) '*** ERROR *** ! Angular momentum l>3 not implemented !'
    end if
  end subroutine evaluate_pao
  !!***
  
!!****f* angular_coeff_routines/pp_elem *
!!
!!  NAME 
!!   pp_elem
!!  USAGE
!!   pp_elem(f_r,l,x_n,y_n,z_n,r,pp_value)
!!  PURPOSE
!!   Forms pseudopotential element for given angular momentum by
!!   multiplying radial value by sum over m of Y_lm's
!!
!!  INPUTS
!!   x_n, y_n, z_n, r : direction cosines, value of radial distance  
!!   l -  ang momentum value
!!   f_r : value of radial function 
!!  USES
!!   datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   30/09/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!

  subroutine pp_elem(f_r,l,m,x_n,y_n,z_n,r,val)
    use datatypes
    implicit none

    real(double), intent(in)  :: f_r,x_n,y_n,z_n,r
    real(double), intent(out) :: val
    integer, intent(in) :: l,m
    real(double) :: x,y,z,theta,phi,r_my

    !unnormalizing direction cosines
    x = x_n*r
    y = y_n*r
    z = z_n*r
    !converting basis from Cartesian params to spherical polars
    call convert_basis(x,y,z,r_my,theta,phi)
    !write(*,*) 'Basis: ',x,y,z,r_my,theta,phi
    !call test_rotation(l,m,theta)
    val = 0.0_double
    val = f_r*re_sph_hrmnc(l,m,theta,phi)
  end subroutine pp_elem
  !!***

!!****f* angular_coeff_routines/pp_elem_derivative *
!!
!!  NAME 
!!   pp_elem_derivative
!!  USAGE
!!   pp_elem(i_vector,f_r,df_r,l,x_n,y_n,z_n,r,l,d_val)
!!  PURPOSE
!!   Evaluates value of gradient of f(r)*Re(Y_lm) along
!!   a specified Cartesian unit vector
!!  INPUTS
!!   x_n, y_n, z_n, r : direction cosines, value of radial distance  
!!   l -  ang momentum value
!!   f_r,df_r : value of radial function and first derivative
!!   i_vector : direction of unit vector (1:x, 2:y, 3:z) 
!!  USES
!!   datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   30/09/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine pao_elem_derivative_2(i_vector,spec,l,nzeta,m,x_i,y_i,z_i,drvtv_val)

    use datatypes
    use numbers

    implicit none
    
    !RC 09/11/03 using (now debugged) routine pp_elem_derivative (see 
    ! above) as template for this sbrt pao_elem_derivative
    real(double), intent(inout) :: x_i,y_i,z_i
    real(double), intent(out) :: drvtv_val
    integer, intent(in) :: i_vector, l, m, spec, nzeta
    integer :: n1,n2
    real(double) :: del_x,xj1,xj2,f_r,df_r,a,b,c,d,alpha,beta,gamma,delta
    real(double) :: x,y,z,r_my,theta,phi,c_r,c_theta,c_phi,x_n,y_n,z_n
    real(double) :: fm_phi, dfm_phi, val1, val2, rl, rl1, tmpr, tmpdr
    real(double), parameter :: mintol = 0.000000001_double
    !routine to calculate value of gradient of f(r)*Re(Y_lm(x,y,z))
    !along specified Cartesian unit vector
    r_my = sqrt((x_i*x_i)+(y_i*y_i)+(z_i*z_i))
    call pao_rad_vals_fetch(spec,l,nzeta,m,r_my,f_r,df_r)
    if(r_my>very_small) then 
       x_n = x_i/r_my; y_n = y_i/r_my; z_n = z_i/r_my
    else
       x_n = zero; y_n = zero; z_n = zero
    end if
    
    call pp_gradient(i_vector,f_r,df_r,x_n,y_n,z_n,r_my,l,m,drvtv_val)
    
  end subroutine pao_elem_derivative_2
!!***    

!!****f* angular_coeff_routines/pao_rad_vals_fetch *
!!
!!  NAME 
!!   pao_rad_vals_fetch
!!  USAGE
!! 
!!  PURPOSE
!!   Spline routine (probably redundant)
!!  INPUTS
!! 
!! 
!!  USES
!! 
!!  AUTHOR
!!   R. Choudhury
!!  CREATION DATE
!!   2003 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine pao_rad_vals_fetch(spec,l,nzeta,m,r,f_r,df_r)

    use datatypes
    use numbers
    use pao_format !,ONLY : pao

    implicit none
    !routine to spline out the values of the radial table of a specified PAO
    integer, intent(in) :: spec,l,m,nzeta
    integer :: n1,n2
    real(double), intent(in) :: r
    real(double), intent(inout) :: f_r,df_r
    real(double) :: del_x,a,b,c,d,xj1,xj2
    real(double) :: alpha,beta,gamma,delta,rl,rl1,tmpr,tmpdr
    
    !RC here have to recall that the SIESTA PAO's are normalised by 1/r**l
    del_x = (pao(spec)%angmom(l)%zeta(nzeta)%cutoff/&
         &(pao(spec)%angmom(l)%zeta(nzeta)%length-1))
    !spline out radial table(r) and d1_radial_table(r)
    !initialise to zero
    n1 = 0; n2 = 0; xj1 = zero; xj2 = zero;a=zero
    b = zero; c = zero; d = zero
    
    n1 = aint(r/del_x)
    n2 = n1+1
    xj1 = n1*del_x
    xj2 = xj1+del_x
    
    if(n2<pao(spec)%angmom(l)%zeta(nzeta)%length) then
       a = (xj2-r)/del_x
       b = (r-xj1)/del_x
       c = (a*a*a-a)*del_x*del_x/six
       d = (b*b*b-b)*del_x*del_x/six
       
       alpha = -one/del_x
       beta = -alpha
       gamma = -del_x*(three*a*a-one)/six
        delta = del_x*(three*b*b-one)/six
       
       f_r = a*pao(spec)%angmom(l)%zeta(nzeta)%table(n1+1)+&
            &b*pao(spec)%angmom(l)%zeta(nzeta)%table(n2+1)+&
            &c*pao(spec)%angmom(l)%zeta(nzeta)%table2(n1+1)+&
            &d*pao(spec)%angmom(l)%zeta(nzeta)%table2(n2+1)
       
       df_r = alpha*pao(spec)%angmom(l)%zeta(nzeta)%table(n1+1)& 
            &+beta*pao(spec)%angmom(l)%zeta(nzeta)%table(n2+1)&
            &+gamma*pao(spec)%angmom(l)%zeta(nzeta)%table2(n1+1)&
            &+delta*pao(spec)%angmom(l)%zeta(nzeta)%table2(n2+1)
       
    else
       f_r = zero
       df_r = zero
    end if
    !RC ended splining..
    !Now changing normalised PAO and PAO derivative into unnormalised values
    if(l>0) then
       rl = r**l
       if(l == 1) then
          rl1 = one
       else
          rl1 = r**(l-1)
       endif
       !if(l==1.AND.r_my<1.0e-8) rl1 = 1.0_double
       tmpr = rl*f_r
       tmpdr = rl*df_r + l*rl1*f_r
       f_r = tmpr
       df_r = tmpdr
    end if
    
  end subroutine pao_rad_vals_fetch
!!***

!!****f* angular_coeff_routines/grad_mat_elem_gen2_prot *
!!
!!  NAME 
!!   grad_mat_elem_gen2_prot
!!  USAGE
!! 
!!  PURPOSE
!!   Produces gradient of matrix element
!!  INPUTS
!! 
!! 
!!  USES
!! 
!!  AUTHOR
!!   R. Choudhury
!!  CREATION DATE
!!   2003 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine grad_mat_elem_gen2_prot(dir,case,sp1,l1,nz1,m1,sp2,l2,nz2,m2,x,y,z,grad_valout)
    use datatypes
    use ol_int_datatypes !,ONLY : ol_index,rad_tables,rad_tables_ke,ol_index_nlpf_pao&
    !&,rad_tables_nlpf_pao

    use spline_module, ONLY: dsplint
    use GenComms, ONLY: inode, ionode, myid !for debugging purposes
    implicit none
    !improved routine to evaluate matrix element derivatives for the following cases
    !1 - pao_pao, 2 - pao_ke_pao, 3 - nlpf_pao (specified by case)
    integer, intent(in) :: dir,case,sp1,l1,nz1,m1,sp2,l2,nz2,m2
    integer :: count,n_lvals,lmax,nzmax,npts,i,l3,l_index,m_index,l,m,ma,mc
    integer :: m1dum,m2dum,l1dum,l2dum
    real(double), intent(in) :: x,y,z
    real(double), intent(out) :: grad_valout
    real(double) :: r,theta,phi,ang_factor,del_x,ind_val,f_r,df_r,grad_val
    real(double) :: c_r,c_theta,c_phi,ylm_factor,dtheta_factor,dphi_factor,num_grad  
    real(double) :: ang_coeff1,ang_coeff2,out_val,arg,grad1,grad2,dummy,grad_val2
    real(double), parameter :: mintol = 0.000000001_double
    logical :: flag
    !just coding for the straight pao_pao case for now, first spline out the function 
    !values that we need
    if(case.lt.3) then !either pao/pao or pao/ke/pao overlap matrix elements
       grad_valout = 0.0_double
       count = ol_index(sp1,sp2,nz1,nz2,l1,l2)
       n_lvals = rad_tables(count)%no_of_lvals
       call convert_basis(x,y,z,r,theta,phi)
       do i = 1,n_lvals
          l3 = rad_tables(count)%l_values(i)
          del_x = rad_tables(count)%rad_tbls(1)%del_x
          npts = rad_tables(count)%rad_tbls(1)%npnts
          if(case.eq.1) then
             call dsplint(del_x,rad_tables(count)%rad_tbls(i)%arr_vals(1:npts), &
                  rad_tables(count)%rad_tbls(i)%arr_vals2(1:npts),npts,r,f_r,df_r,flag)
          else!case must equal 2
             call dsplint(del_x,rad_tables_ke(count)%rad_tbls(i)%arr_vals(1:npts), &
                  rad_tables_ke(count)%rad_tbls(i)%arr_vals2(1:npts),npts,r,f_r,df_r,flag)
          endif
          !have now collected f_r and df_r, next to evaluate the required gradient
          call construct_gradient(l1,l2,l3,m1,m2,dir,f_r,df_r,x,y,z,grad_val)
          grad_valout = grad_valout+grad_val
       enddo
    else !case must be 3 nlpf/pao tables
       grad_valout = 0.0_double
       count = ol_index_nlpf_pao(sp1,sp2,nz1,nz2,l1,l2)
       n_lvals = rad_tables_nlpf_pao(count)%no_of_lvals
       call convert_basis(x,y,z,r,theta,phi)
       do i = 1,n_lvals
          l3 = rad_tables_nlpf_pao(count)%l_values(i)
          del_x = rad_tables_nlpf_pao(count)%rad_tbls(1)%del_x
          npts = rad_tables_nlpf_pao(count)%rad_tbls(1)%npnts
          call dsplint(del_x,rad_tables_nlpf_pao(count)%rad_tbls(i)%arr_vals(1:npts), &
                  rad_tables_nlpf_pao(count)%rad_tbls(i)%arr_vals2(1:npts),npts,r,f_r,df_r,flag)
          call construct_gradient(l1,l2,l3,m1,m2,dir,f_r,df_r,x,y,z,grad_val)
          grad_valout = grad_valout+grad_val
       enddo
       continue
    endif
    
  end subroutine grad_mat_elem_gen2_prot
!!***

!!****f* angular_coeff_routines/construct_gradient *
!!
!!  NAME 
!!   construct_gradient
!!  USAGE
!! 
!!  PURPOSE
!!   Builds a gradient
!!  INPUTS
!! 
!! 
!!  USES
!! 
!!  AUTHOR
!!   R. Choudhury
!!  CREATION DATE
!!   2003 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine construct_gradient(l1,l2,l3,m1,m2,dir,f_r,df_r,x,y,z,grad_val)
    use datatypes
    use GenComms, ONLY: inode, ionode, myid !for debugging purposes
    use ol_int_datatypes !,ONLY : coefficients,
    !use gaussian_test_routines, ONLY: grad_find_cartesian
    !use cubic_spline_routines
    !use spline_module, ONLY: dsplint
    implicit none
    !routine to construct(the)gradient for (real) PAO matrix elements 
    !in the direction specified by dir
    !have now collected f_r and df_r, next to evaluate the required gradient
    integer, intent(in) :: l1,l2,l3,m1,m2,dir
    real(double), intent(in) :: x,y,z,f_r,df_r
    real(double), intent(out) :: grad_val
    integer :: ma,mc,l_index,m_index,l1dum,l2dum,m1dum,m2dum
    real(double) :: ang_coeff1,ang_coeff2,out_val,out_val2

    if((m1.ge.0).and.(m2.ge.0)) then
       !gradient component 1
       ma = m1-m2
       if(abs(ma).gt.l3) then !zero out unwanted values
          ang_coeff1 = 0.0_double
          continue
       else
          call calc_index_new(l1,l2,l3,-m1,m2,ma,l_index,m_index)
          ang_coeff1 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,-ma,1,dir,f_r,df_r,x,y,z,out_val)
          ang_coeff1 = ang_coeff1*out_val
          ang_coeff1 = ang_coeff1*((-1)**m2)
       endif
       !gradient component 2
       mc = -(m1+m2)
       if(abs(mc).gt.l3) then
          ang_coeff2 = 0.0_double
       else
          call calc_index_new(l1,l2,l3,m1,m2,mc,l_index,m_index)
          ang_coeff2 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,mc,1,dir,f_r,df_r,x,y,z,out_val)
          ang_coeff2 = ang_coeff2*out_val
       endif
    else if((m1.lt.0).and.(m2.lt.0)) then
       !gradient component 1
       ma = m1-m2
       if(abs(ma).gt.l3) then !zero out unwanted values
          ang_coeff1 = 0.0_double
       else
          call calc_index_new(l1,l2,l3,-m1,m2,ma,l_index,m_index)
          ang_coeff1 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,ma,1,dir,f_r,df_r,x,y,z,out_val)
          ang_coeff1 = ang_coeff1*out_val
       endif
       !gradient component 2
       mc = -(m1+m2)
       if(abs(mc).gt.l3) then
          ang_coeff2 = 0.0_double
       else
          call calc_index_new(l1,l2,l3,m1,m2,mc,l_index,m_index)
          ang_coeff2 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,mc,1,dir,f_r,df_r,x,y,z,out_val)        
          ang_coeff2 = -ang_coeff2*out_val
       endif
       ang_coeff1 = ang_coeff1*((-1)**m1)
    else!m1 and m2 have different signs
       call fix_signs(l1,l2,m1,m2,l1dum,l2dum,m1dum,m2dum)
       !gradient component 1
       ma = m1dum-m2dum
       if(abs(ma).gt.l3) then
          ang_coeff1 = 0.0_double
       else
          call calc_index_new(l1dum,l2dum,l3,-m1dum,m2dum,ma,l_index,m_index)
          ang_coeff1 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,ma,-1,dir,f_r,df_r,x,y,z,out_val)
          ang_coeff1 = ang_coeff1*out_val
       endif
       mc = -(m1+m2)
       if(abs(mc).gt.l3) then
          ang_coeff2 = 0.0_double
       else
          call calc_index_new(l1,l2,l3,m1,m2,mc,l_index,m_index)
          ang_coeff2 = coefficients(l_index)%m_combs(m_index)
          call grad_find(l3,-mc,-1,dir,f_r,df_r,x,y,z,out_val)
          ang_coeff2 = ang_coeff2*out_val
       endif
       !now take care of normalization
       ang_coeff1 = ang_coeff1*((-1)**(m1dum+1))
       ang_coeff2 = ang_coeff2*((-1)**(mc))
    endif
    grad_val = 8.0_double*(ang_coeff1+ang_coeff2)*ol_norm(m1,m2)
    
  end subroutine construct_gradient
!!***  
  subroutine fix_signs(l1,l2,m1,m2,l1dum,l2dum,m1dum,m2dum)
    !routine to make sure m1dum.ge.0, m2dum.lt.0
    !assumes that m1 and m2 differ in sign initially
    integer, intent(in) :: l1,l2,m1,m2
    integer, intent(out) :: l1dum,l2dum,m1dum,m2dum
    if(m1.ge.0) then
       l1dum = l1; l2dum = l2
       m1dum = m1; m2dum = m2
    else
       l1dum = l2; l2dum = l1
       m1dum = m2; m2dum = m1
    endif
       
  end subroutine fix_signs
      
  subroutine grad_find(l,m,arg,direction,f_r,df_r,x,y,z,out_val)
    use datatypes
    use GenComms, ONLY: inode, ionode, myid !for debugging purposes
    implicit none
    !routine to select gradient in the correct direction
    integer, intent(in) :: l,m,arg,direction
    real(double), intent(in) :: f_r,df_r,x,y,z
    real(double), intent(out) :: out_val
    real(double) :: r
    !direction is 1:x, 2:y, 3:z
    !initialising output to zero..
    out_val = 0.0_double
    
    select case(direction)
    case(1) !gradient along x direction
       call make_xy_paogradient_comps(l,m,x,y,z,arg,1,f_r,df_r,out_val)
    case(2) !along y
       call make_xy_paogradient_comps(l,m,x,y,z,arg,-1,f_r,df_r,out_val)
    case(3) !along z
       call make_z_paogradient_comps(l,m,x,y,z,arg,f_r,df_r,out_val)
    end select
  end subroutine grad_find

  subroutine pp_gradient_x(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    use datatypes
    implicit none
    !routine to evaluate gradient of f(r)*Re(Ylm(thet,phi)) in the x
    !direction
    real(double), intent(in) :: f_r,df_r,x_n,y_n,z_n,r
    real(double), intent(out) :: d_val
    integer, intent(in) :: l,m
    integer :: dir
    real(double) :: x,y,z,r_my,theta,phi,c_r,c_theta,c_phi
    real(double) :: fm_phi, dfm_phi, val1, val2,denom1,denom2
    real(double), parameter :: mintol = 0.000000001_double
    real(double), parameter :: epsilon = 0.0001_double
    real(double) x_comp_1,x_comp_2,x_comp_3,x_comp_4,coeff1,coeff2
    real(double), parameter :: pi = 3.1415926535897932_double
    !unnormalize the direction cosines
    x = x_n*r
    y = y_n*r
    z = z_n*r
    !convert from Cartesian system to spherical polars
    call convert_basis(x,y,z,r_my,theta,phi)
    !if zero radius then lets get out of here..
    if(abs(r).lt.mintol) then
       d_val = 0.0_double
       return
    else
       continue
    endif
    dir = 1 !telling fix_dval which gradient we are taking
    call make_grad_prefacs(x_comp_1,x_comp_2,x_comp_3,x_comp_4,coeff1,coeff2,df_r,f_r,r,l,m)
    !write(*,*) x_comp_1,x_comp_2,x_comp_3,x_comp_4,'x_comps'
    !now actually calculate and sum the gradient components 
    !RC need to fix the equations for the case where l=0
    if(abs(theta).lt.epsilon) then
       !write(*,*) 'theta small condition satisfied'
       x_comp_1 = x_comp_1*coeff1*sph_hrmnc_z(l+1,m+1,theta)
       x_comp_3 = -x_comp_3*coeff1*sph_hrmnc_z(l+1,m-1,theta)
       x_comp_2 = -x_comp_2*coeff2*sph_hrmnc_z(l-1,m+1,theta)
       x_comp_4 = x_comp_4*coeff2*sph_hrmnc_z(l-1,m-1,theta)
       d_val =  x_comp_1+x_comp_2+x_comp_3+x_comp_4
       call fix_dval(m,d_val,dir)
    else if(theta.lt.pi+epsilon.and.theta.gt.pi-epsilon) then !theta near pi
       x_comp_1 = x_comp_1*coeff1*sph_hrmnc_z(l+1,m+1,theta)
       x_comp_2 = -x_comp_2*coeff2*sph_hrmnc_z(l-1,m+1,theta)
       x_comp_3 = -x_comp_3*coeff1*sph_hrmnc_z(l+1,m-1,theta)
       x_comp_4 = x_comp_4*coeff2*sph_hrmnc_z(l-1,m-1,theta)
       d_val = x_comp_1+x_comp_2+x_comp_3+x_comp_4
       call fix_dval(m,d_val,dir)
    else
       x_comp_1 =  x_comp_1*coeff1*prefac(l+1,m+1)*assoclegpol(l+1,m+1,theta)
       x_comp_2 = -x_comp_2*coeff2*prefac(l-1,m+1)*assoclegpol(l-1,m+1,theta)
       x_comp_3 = -x_comp_3*coeff1*prefac(l+1,m-1)*assoclegpol(l+1,m-1,theta)
       x_comp_4 =  x_comp_4*coeff2*prefac(l-1,m-1)*assoclegpol(l-1,m-1,theta)
       call pp_gradient_x_multiply(x_comp_1,x_comp_2,x_comp_3,x_comp_4,m,phi,d_val)
    endif

  end subroutine pp_gradient_x
  
  subroutine pp_gradient_x_multiply(x_comp_1,x_comp_2,x_comp_3,x_comp_4,m,phi,d_val)
    use datatypes
    implicit none
    !routine to choose between post-mutiplying by sines or cosines depending
    !on the sign of m
    integer, intent(in) :: m
    real(double), intent(in) :: x_comp_1,x_comp_2,x_comp_3,x_comp_4,phi
    real(double), intent(inout) :: d_val
    
    if(m.ge.0) then
       d_val = (cos((m+1)*phi)*(x_comp_1+x_comp_2))+(cos((m-1)*phi))*(x_comp_3+x_comp_4)
       if(m.eq.0) then
          d_val = (cos((m+1)*phi)*(x_comp_1+x_comp_2))+(cos((m-1)*phi))*(x_comp_3+x_comp_4)
          !write(*,*) cos((m+1)*phi),x_comp_1+x_comp_2,cos((m-1)*phi),x_comp_3+x_comp_4
          d_val = d_val/sqrt(2.0_double)
          !write(*,*) d_val, 'd_val'
       else
          continue
       endif
    else !m.lt.0
       d_val = (sin((m+1)*phi)*(x_comp_1+x_comp_2))+((sin((m-1)*phi))*(x_comp_3+x_comp_4))
    endif
  end subroutine pp_gradient_x_multiply

  subroutine pp_gradient_y(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    use datatypes
    implicit none
    !routine to evaluate gradient of f(r)*Re(Ylm(thet,phi)) in the y
    !direction
    real(double), intent(in) :: f_r,df_r,x_n,y_n,z_n,r
    real(double), intent(out) :: d_val
    integer, intent(in) :: l,m
    integer :: dir
    real(double) :: x,y,z,r_my,theta,phi,c_r,c_theta,c_phi
    real(double) :: fm_phi, dfm_phi, val1, val2,denom1,denom2
    real(double), parameter :: mintol = 0.000000001_double
    real(double), parameter :: epsilon = 0.000001_double
    real(double) y_comp_1,y_comp_2,y_comp_3,y_comp_4,coeff1,coeff2
    real(double), parameter :: pi = 3.1415926535897932_double

    !unnormalise the direction cosines
    x = x_n*r
    y = y_n*r
    z = z_n*r
    !find the relevant spherical polar coordinates
    call convert_basis(x,y,z,r_my,theta,phi)
    !if zero radius then lets get out of here..
    if(abs(r).lt.mintol) then
       d_val = 0.0_double
       return
    else
       continue
    endif
    call make_grad_prefacs(y_comp_1,y_comp_2,y_comp_3,y_comp_4,coeff1,coeff2,df_r,f_r,r,l,m)
    dir = 2 !telling fix_dval which direction we are taking the gradient in
    if(abs(theta).lt.epsilon) then
       !write(*,*) 'theta small condition satisfied'
       y_comp_1 =  y_comp_1*coeff1*sph_hrmnc_z(l+1,m+1,theta)
       y_comp_2 = -y_comp_2*coeff2*sph_hrmnc_z(l-1,m+1,theta)
       y_comp_3 =  y_comp_3*coeff1*sph_hrmnc_z(l+1,m-1,theta)
       y_comp_4 = -y_comp_4*coeff2*sph_hrmnc_z(l-1,m-1,theta)
       d_val = y_comp_1+y_comp_2+y_comp_3+y_comp_4
       call fix_dval(m,d_val,dir)
    else if(theta.lt.pi+epsilon.and.theta.gt.pi-epsilon) then !theta near pi
       y_comp_1 = y_comp_1*coeff1*sph_hrmnc_z(l+1,m+1,theta)
       y_comp_2 = -y_comp_2*coeff2*sph_hrmnc_z(l-1,m+1,theta)
       y_comp_3 = y_comp_3*coeff1*sph_hrmnc_z(l+1,m-1,theta)
       y_comp_4 = -y_comp_4*coeff2*sph_hrmnc_z(l-1,m-1,theta)
       d_val = y_comp_1+y_comp_2+y_comp_3+y_comp_4
       call fix_dval(m,d_val,dir)
    else
       y_comp_1 =  y_comp_1*coeff1*prefac(l+1,m+1)*assoclegpol(l+1,m+1,theta)
       y_comp_2 = -y_comp_2*coeff2*prefac(l-1,m+1)*assoclegpol(l-1,m+1,theta)
       y_comp_3 =  y_comp_3*coeff1*prefac(l+1,m-1)*assoclegpol(l+1,m-1,theta)
       y_comp_4 = -y_comp_4*coeff2*prefac(l-1,m-1)*assoclegpol(l-1,m-1,theta)
       call pp_gradient_y_multiply(y_comp_1,y_comp_2,y_comp_3,y_comp_4,m,phi,d_val)
    endif
  end subroutine pp_gradient_y

  subroutine pp_gradient_y_multiply(y_comp_1,y_comp_2,y_comp_3,y_comp_4,m,phi,d_val)
    use datatypes
    implicit none
    !routine to decide whether to post-multiply y derivative with cos(phi) or
    !with sin(phi)
    integer, intent(in) :: m
    real(double), intent(in) :: y_comp_1,y_comp_2,y_comp_3,y_comp_4,phi
    real(double), intent(inout) :: d_val
    
    if(m.ge.0) then
       d_val = (sin((m+1)*phi)*(y_comp_1+y_comp_2))+(sin((m-1)*phi))*(y_comp_3+y_comp_4)
       if(m.eq.0) then
          d_val = (sin((m+1)*phi)*(y_comp_1+y_comp_2))+(sin((m-1)*phi))*(y_comp_3+y_comp_4)
          d_val = d_val/sqrt(2.0_double)
       else
          continue
       endif
    else !m.lt.0
       d_val = -(cos((m+1)*phi)*(y_comp_1+y_comp_2))-((cos((m-1)*phi))*(y_comp_3+y_comp_4))
    endif
    
  end subroutine pp_gradient_y_multiply

  subroutine pp_gradient_z(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    use datatypes
    implicit none
    !code to calculate PAO gradients in the z direction..
    integer, intent(in) :: l,m
    real(double), intent(in) :: f_r,df_r,x_n,y_n,z_n,r
    real(double), intent(out) :: d_val
    real(double) :: x,y,z,pref1,pref2,coeff1,coeff2,z_comp_1,z_comp_2
    real(double) :: r_my,theta,phi
    real(double) :: denom1,denom2
    real(double), parameter :: mintol = 0.000000001_double
    real(double), parameter :: epsilon = 0.0001_double
    
    !unnormalize direction cosines and convert to spherical coordinates
    x = x_n*r; y = y_n*r; z = z_n*r
    call convert_basis(x,y,z,r_my,theta,phi)
    !if zero radius then lets get out of here..
    !if(abs(r).lt.mintol) then
    !   d_val = 0.0_double
    !   return
    !else
    !   continue
    !endif
    denom1 = (2.0_double*l+1.0_double)*(2.0_double*l+3.0_double)
    denom2 = (2.0_double*l-1.0_double)*(2.0_double*l+1.0_double)
    pref1 = sqrt((((l+1.0_double)**2)-(m**2))/denom1)
    pref2 = sqrt(((l**2)-(m**2))/denom2)
    if(r.gt.epsilon) then
       coeff1 = (df_r-(l*f_r/r)); coeff2 = (df_r+((l+1.0_double)*f_r/r))
    else
       coeff1 = df_r; coeff2 = df_r
    end if
    z_comp_1 = pref1*coeff1; z_comp_2 = pref2*coeff2
    if(abs(theta).lt.epsilon) then
       !write(*,*) 'theta small condition satisfied'
       if(m.ge.0) then
          z_comp_1 = z_comp_1*sph_hrmnc_z(l+1,m,theta)
          z_comp_2 = z_comp_2*sph_hrmnc_z(l-1,m,theta)
          d_val = z_comp_1+z_comp_2
          if(m.gt.0) then
             d_val = d_val*sqrt(2.0_double)
          else
             d_val = d_val
          endif
       else !m.lt.0
          d_val = 0.0_double
       endif
    else
       z_comp_1 = z_comp_1*prefac(l+1,m)*assoclegpol(l+1,m,theta)
       z_comp_2 = z_comp_2*prefac(l-1,m)*assoclegpol(l-1,m,theta)
       if(m.gt.0) then
          d_val = sqrt(2.0_double)*cos(m*phi)*(z_comp_1+z_comp_2)
       else if(m.eq.0) then 
          d_val = (z_comp_1+z_comp_2)
       else !m.lt.0
          d_val = sqrt(2.0_double)*sin(m*phi)*(z_comp_1+z_comp_2)
       endif
    endif
    
  end subroutine pp_gradient_z
  
  subroutine pp_gradient(i_vector,f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    use datatypes
    use GenComms, ONLY: inode, ionode, myid !for debugging purposes
    implicit none
    !calculate pp gradients for arbitrary directions,
    !so long as they're Cartesian
    integer, intent(in) :: i_vector,l,m
    real(double), intent(in) :: f_r,df_r,x_n,y_n,z_n,r
    real(double), intent(out) :: d_val
    real(double) :: x,y,z,out_val
    integer :: arg,dir
    !also testing make_xy_pao_gradient_comps subroutine

    !setting up variables for make_xy..
    if(m.lt.0) then 
       arg = -1
    else
       arg = 1
    endif
    x = x_n*r; y = y_n*r; z = z_n*r
    if(i_vector.eq.1) then
       dir = 1
       call pp_gradient_x(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    else if(i_vector.eq.2) then
       dir = -1
       call pp_gradient_y(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    else !i_vector must be 3
       call pp_gradient_z(f_r,df_r,x_n,y_n,z_n,r,l,m,d_val)
    endif
    
  end subroutine pp_gradient

  subroutine make_xy_paogradient_comps(l,m,x,y,z,arg,dir,f_r,df_r,out_val)
    use datatypes
    implicit none
    !routine to generate common expressions required by x and y gradient
    !routines..
    integer, intent(in) :: l,m,arg,dir
    real(double), intent(in) :: x,y,z,f_r,df_r
    real(double), intent(out) :: out_val
    real(double) :: comp1,comp2,comp3,comp4,coeff1,coeff2,r,theta,phi
    real(double), parameter :: epsilon = 0.0000001_double
    real(double), parameter :: pi = 3.1415926535897932_double
    !arg=-(+)1 indicating sine(cosine) phi term
    !dir=1(2) indicating x(y) direction gradient is being calculated
    !convert coordinates
    call convert_basis(x,y,z,r,theta,phi)
    !make some prefactors
    call make_grad_prefacs(comp1,comp2,comp3,comp4,coeff1,coeff2,df_r,f_r,r,l,m)
    comp1=comp1*coeff1;comp2=comp2*coeff2;comp3=comp3*coeff1;comp4 = comp4*coeff2
    if(abs(theta).lt.epsilon.or.(theta.lt.pi+epsilon.and.theta.gt.pi-epsilon)) then
       if(arg.eq.1) then
          if(dir.eq.1) then
             out_val = (comp1*sph_hrmnc_z(l+1,m+1,theta))+(-comp2*sph_hrmnc_z(&
                  &l-1,m+1,theta))+(-comp3*sph_hrmnc_z(l+1,m-1,theta))+(&
                  &comp4*sph_hrmnc_z(l-1,m-1,theta))
          else!dir.eq.-1
             out_val = 0.0_double
          endif
       else!arg.eq.-1
          if(dir.eq.1) then
             out_val = 0.0_double
          else!dir.eq.-1
             out_val = -((comp1*sph_hrmnc_z(l+1,m+1,theta))-(comp2*sph_hrmnc_z(l-1,m+1,theta)&
                  &)+(comp3*sph_hrmnc_z(l+1,m-1,theta))-(comp4*sph_hrmnc_z(l-1,m-1,theta)))
          endif
       endif
       out_val = out_val*sqrt(2.0_double)
    else       
       comp1 = comp1*prefac(l+1,m+1)*assoclegpol(l+1,m+1,theta)
       comp2 = comp2*prefac(l-1,m+1)*assoclegpol(l-1,m+1,theta)
       comp3 = comp3*prefac(l+1,m-1)*assoclegpol(l+1,m-1,theta)
       comp4 = comp4*prefac(l-1,m-1)*assoclegpol(l-1,m-1,theta)
       if(dir.eq.-1) then
          if(arg.eq.-1) then !sine combination, y direction gradient
             out_val = -(((comp1-comp2)*cos((m+1)*phi))+(cos((m-1)*phi)*(comp3-comp4)))
          else !arg must equal +1
             out_val = ((comp1-comp2)*sin((m+1)*phi))+((comp3-comp4)*sin((m-1)*phi))
          endif
       else !dir is 1, x direction gradient
          if(arg.eq.1) then !cosine combination
             out_val = ((comp1-comp2)*cos((m+1)*phi))+((-comp3+comp4)*cos((m-1)*phi))
          else !arg must be -1
             out_val = ((comp1-comp2)*sin((m+1)*phi))+((-comp3+comp4)*sin((m-1)*phi))
          endif
       endif
       out_val = out_val*sqrt(2.0_double)
    endif
  end subroutine make_xy_paogradient_comps

  subroutine make_z_paogradient_comps(l,m,x,y,z,arg,f_r,df_r,out_val)
    use datatypes
    implicit none
    !routine to do what it says on the tin
    integer, intent(in) :: l,m,arg
    real(double), intent(in) :: x,y,z,f_r,df_r
    real(double), intent(out) :: out_val
    real(double) :: denom1,denom2,pref1,pref2,coeff1,coeff2,comp1,comp2
    real(double) :: r,theta,phi
    real(double), parameter :: epsilon = 0.0000001_double
    real(double), parameter :: pi = 3.1415926535897932_double
    !n.b. arg indicates the sign of the sph hrmnc combinations 
    call convert_basis(x,y,z,r,theta,phi)
    !if zero radius then lets get out of here..
    !if(abs(r).lt.epsilon) then
    !   out_val = 0.0_double
    !   return
    !else
    !   continue
    !endif
    denom1 = (2.0_double*l+1.0_double)*(2.0_double*l+3.0_double)
    denom2 = (2.0_double*l-1.0_double)*(2.0_double*l+1.0_double)
    pref1 = sqrt((((l+1.0_double)**2)-(m**2))/denom1)
    pref2 = sqrt(((l**2)-(m**2))/denom2)
    if(r.gt.epsilon) then
       coeff1 = (df_r-(l*f_r/r)); coeff2 = (df_r+((l+1.0_double)*f_r/r))
    else
       coeff1 = df_r; coeff2 = df_r
    endif
    comp1 = pref1*coeff1; comp2 = pref2*coeff2

    if(abs(theta).lt.epsilon.or.(theta.lt.pi+epsilon.and.theta.gt.pi-epsilon)) then
    !   !write(*,*) 'theta small condition satisfied'
       if(arg.eq.1) then
          comp1 = comp1*sph_hrmnc_z(l+1,m,theta)
          comp2 = comp2*sph_hrmnc_z(l-1,m,theta)
          out_val = (comp1+comp2)*(2.0_double)
        else !arg.eq.-1
          out_val = 0.0_double
       endif
    else
       comp1 = comp1*prefac(l+1,m)*assoclegpol(l+1,m,theta)
       comp2 = comp2*prefac(l-1,m)*assoclegpol(l-1,m,theta)
       if(arg.eq.1) then
          out_val = 2.0_double*cos(m*phi)*(comp1+comp2)
       else !arg.eq.-1
          out_val = 2.0_double*sin(m*phi)*(comp1+comp2)
       endif
    endif
    
  end subroutine make_z_paogradient_comps
  
  subroutine fix_dval(m,d_val,dir)
    use datatypes
    implicit none
    !routine to shorten the pp_gradient_i routines
    integer, intent(in) :: m,dir
    real(double), intent(inout) :: d_val
    if(dir.eq.1) then
       if(m.gt.0) then
          d_val = d_val
       else
          if(m.eq.0) then
             d_val = d_val/sqrt(2.0_double)
          else
             d_val = 0.0_double
             continue
          endif
       endif
    else if(dir.eq.2) then
       if(m.lt.0) then
          d_val = -d_val
       else
          if(m.eq.0) then
             d_val = d_val/sqrt(2.0_double)
          else
             d_val = 0.0_double
             continue
          endif
       endif
    endif
    
  end subroutine fix_dval
    
  subroutine make_grad_prefacs(pref1,pref2,pref3,pref4,coeff1,coeff2,df_r,f_r,r,l,m)
    use datatypes
    implicit none
    !just code to make simple gradient prefactors
    real(double), intent(in) :: df_r,f_r,r
    real(double), intent(out) :: pref1,pref2,pref3,pref4,coeff1,coeff2
    integer, intent(in) :: l,m
    real(double) :: denom1,denom2
    real(double), parameter :: epsilon = 0.0000001_double

    !need to take care of the situation at the origin
    if(r.gt.epsilon) then
       coeff1 = df_r-(l*f_r/r)
       coeff2 = df_r+(((l+1)/r)*f_r)
    else
       coeff1 = df_r; coeff2 = df_r
    endif

    denom1 = 2.0_double*(2.0_double*l+1.0_double)*(2.0_double*l+3.0_double)
    denom2 = 2.0_double*(2.0_double*l-1.0_double)*(2.0_double*l+1.0_double)
    
    pref1 = sqrt((l+m+1.0_double)*(l+m+2.0_double)/denom1)
    pref2 = sqrt((l-m-1.0_double)*(l-m)/denom2)
    pref3 = sqrt((l-m+1.0_double)*(l-m+2.0_double)/denom1)
    pref4 = sqrt((l+m-1.0_double)*(l+m)/denom2)   

  end subroutine make_grad_prefacs
  
  function ol_norm(m1,m2)

    use datatypes

    implicit none

    !function to handle the root(2) normalization factors that 
    !arise during overlap integral calculation

    integer, intent(in) :: m1,m2
    real(double) :: ol_norm

    if(m1.eq.0.and.m2.eq.0) then
       ol_norm = 0.25_double
    else if(m1.ne.0.and.m2.ne.0) then
       ol_norm = 0.5_double
    else !one is zero and the other is not
       ol_norm = 1.0_double/(2.0_double*sqrt(2.0_double))
    end if
  end function ol_norm

!!****f* angular_coeff_routines/assoclegpol *
!!
!!  NAME 
!!   assoclegpol
!!  USAGE
!!   assoclegpol(l,m,x)
!!  PURPOSE
!!   Function to return value of associated Legendre Polynomial 
!!   having parameters l,m.
!!  INPUTS
!!   l,m, parameters describing Associated Legendre Polynomial
!!   x - argument of associated Legendre polynomial
!!  USES
!!   datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   24/07/03
!!  MODIFICATION HISTORY
!!   2007/01/25 08:21 dave
!!    Removed two assoc. leg. pol routines and combined into one
!!  SOURCE
!!
  function assoclegpol(l,m1,theta)
    use datatypes
    use numbers
    implicit none
    !function to generate the value of the l,mth associated
    !Legendre polynomial with argument x
    real(double) :: assoclegpol
    real(double) :: val_mm,val_mm1,val_mm2
    real(double) :: sto_x,factor,factor2,sto_x_test
    real(double) :: x,x_dashed,theta
    integer i,j,k
    integer l,m1,m
    !Routine based on recursion relations in Numerical Recipes
    !6.6.7
    if(l<0) then
       assoclegpol = zero
       return
    endif
    
    m = abs(m1)
    if(m>l) then
       assoclegpol = zero
       return
    endif
    !evaluate val_mm
    val_mm = one
    !sto_x = sqrt((one-x)*(one+x))
    !x_dashed = acos(x)
    x = cos(theta)
    sto_x = sin(theta)
    !write(*,*) sto_x,'sto_x'
    
    if(m>0) then
       do i=1,2*m-1,2
          val_mm = val_mm*i
       enddo
       do i=1,m
          !val_mm = val_mm*(-1)*(sto_x)
          !RC removing Condon-Shortley phase factor
          val_mm = val_mm*sto_x
       enddo
    end if ! m>0
    if(m==l) then
       assoclegpol = val_mm
    else
       val_mm1 = x*(two*m+1)*val_mm
       if(m+1==l) then
          assoclegpol = val_mm1
       else
          !now use recursion relation to find val_ml(x)
          if(l>m+1) then
             do i = m+2,l
                val_mm2 = one/(i-m)*((x*(two*i-1)*val_mm1) - ((i+m-1)*val_mm))
                val_mm = val_mm1
                val_mm1 = val_mm2
             enddo
             assoclegpol = val_mm2
          else
             assoclegpol = one
          end if
       end if ! m+1==l
    end if ! m==l

    !if m is negative we use Arfken 12.81a to convert the 
    !P_{lm} with positive m to the required value with negative m

    if(m/=m1) then !input m1 must be negative
       factor2 = (fact(l-m))/(fact(l+m))
       assoclegpol = assoclegpol*((-1)**(m))*factor2
    else
       continue
    endif
  end function assoclegpol
!!***

!!****s* angular_coeff_routines/set_prefac *
!!
!!  NAME 
!!   set_prefac
!!  USAGE
!!   set_prefac
!!  PURPOSE
!!   Calculates prefactor of Wigner 3-j coefficients and stores
!!  INPUTS
!!   l,m angular momenta
!! 
!!  USES
!!   datatypes
!!  AUTHOR
!!   T. Miyazaki
!!  CREATION DATE
!!   2005 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine set_prefac

    use datatypes
    use numbers, ONLY: one, four, pi

    implicit none

    integer :: ll, mm
    real(double) :: g, h

    prefac(:,:) = one
    do ll = 0, lmax_prefac
       do mm = -ll, ll
          g = fact(ll-mm)/fact(ll+mm)
          h = (2*ll+1)/(four*pi)
          prefac(ll,mm) = sqrt(g*h)
       enddo
    enddo
    return
  end subroutine set_prefac
!!***

!!****s* angular_coeff_routines/set_prefac_real *
!!
!!  NAME 
!!   set_prefac_real
!!  USAGE
!!   set_prefac_real
!!  PURPOSE
!!   Calculates prefactor of Wigner 3-j coefficients and stores
!!  INPUTS
!!   l,m angular momenta
!! 
!!  USES
!!   datatypes
!!  AUTHOR
!!   T. Miyazaki
!!  CREATION DATE
!!   2005 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine set_prefac_real

    use datatypes
    use numbers, ONLY: one, two, four, twopi

    implicit none

    integer :: ll, mm
    real(double) :: g, h

    prefac_real(:,:) = one
    do ll = 0, lmax_prefac
       do mm = -ll, ll
          g = fact(ll-mm)/fact(ll+mm)
          if(mm/=0) then
             h = (2*ll+1)/(twopi)
          else
             h = (2*ll+1)/(two*twopi)
          endif

          prefac_real(ll,mm) = sqrt(g*h)
          !write(*,*) 'pfr: ',ll,mm,ll-mm,ll+mm,2*ll+1,prefac_real(ll,mm)
       enddo
    enddo
    return
  end subroutine set_prefac_real
!!***

!!****f* angular_coeff_routines/re_sph_hrmnc *
!!
!!  NAME 
!!   re_sph_hrmnc
!!  USAGE
!!   re_sph_hrmnc(l,m,theta,phi)
!!  PURPOSE
!!   calculates value of real spherical harmonic
!!  INPUTS
!!   l,m angular momenta
!!   theta, phi - spherical polar coords, z = rcos(theta)
!!  USES
!!   datatypes
!!  AUTHOR
!!   R Choudhury
!!  CREATION DATE
!!   25/09/03
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!

  function re_sph_hrmnc(l,m,theta,phi)
    use datatypes
    use numbers
    implicit none
    !function to return the value of real spherical harmonic
    !at given value of the solid angle
    integer :: i
    integer, intent(in) :: l,m
    real(double), intent(in) :: theta,phi
    real(double) :: re_sph_hrmnc,val,val_chk,beta,del,val_chk2
    
    val = 0.0_double
    val = prefac_real(l,m)*assoclegpol(l,m,theta)
    if(m.lt.0) then
       val = val*sin(m*phi)
    else
       val = val*cos(m*phi)
    endif
    re_sph_hrmnc = val

  end function re_sph_hrmnc
!!***

  function sph_hrmnc_z(l,m,theta)
    use datatypes
    use numbers
    implicit none
    !function to return value of spherical harmonic on the z-axis
    integer, intent(in) :: l,m
    real(double), intent(in) :: theta
    real(double) :: sph_hrmnc_z,part
    
    if(l.lt.0) then
       return
    else
       continue
    endif
    if(abs(m).gt.l) then
       sph_hrmnc_z = zero
    else
       continue
       if(m==0) then
          part = sqrt((two*l+one)/(four*pi))
          
          if(abs(theta).lt.0.0001_double) then !theta roughly zero
             sph_hrmnc_z = part
          else
             !theta is in vicinity of pi
             if(theta.lt.pi+0.0001_double.and.theta.gt.pi-0.0001_double) then
                sph_hrmnc_z = ((-1)**l)*part
             else
                continue
             endif
          endif
          
       else
          sph_hrmnc_z = zero
       endif
    endif
    
  end function sph_hrmnc_z

!!****s* angular_coeff_routines/set_fact *
!!
!!  NAME 
!!   set_fact
!!  USAGE
!!   set_fact
!!  PURPOSE
!!   Calculates factorial and stores
!!  INPUTS
!! 
!!  USES
!!   datatypes
!!  AUTHOR
!!   T. Miyazaki
!!  CREATION DATE
!!   2005 sometime
!!  MODIFICATION HISTORY
!!
!!  SOURCE
!!
  subroutine set_fact
    use datatypes
    use numbers, ONLY: one
    implicit none
    real(double) :: xx
    integer :: ii

    fact(-1:lmax_fact) = one
    do ii=1, lmax_fact
       xx = real(ii,double)
       fact(ii)=fact(ii-1)* xx
    enddo
    return
  end subroutine set_fact
!!***

end module angular_coeff_routines



