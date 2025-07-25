!copyright (C) 2001  MSC-RPN COMM  %%%RPNPHY%%%

      SUBROUTINE SOIL_FREEZING(DT, TSOIL, VEGL, VEGH, PSN, PSNVH,  &
                                SOILCONDZ, SOILHCAPZ , TGRS, TVEGS,   &
                                WSOIL, ISOIL,  &
                                SNORO, SNODP, TSNO, &
                                SNVRO, SNVDP, TSNV, &
                                TDEEP, WUNFRZ, N)


      USE TDPACK
      USE SFC_OPTIONS
      USE SVS_CONFIGS

      IMPLICIT NONE

      ! Input
      INTEGER N ! Number of grid points

      REAL DT

      REAL, DIMENSION(N)        :: VEGL, VEGH, PSN, PSNVH, TGRS, TDEEP,TVEGS
      REAL, DIMENSION(N)        :: SNORO, SNODP, TSNO 
      REAL, DIMENSION(N)        :: SNVRO, SNVDP, TSNV 
      REAL, DIMENSION(N,NL_SVS) :: TSOIL,SOILCONDZ, SOILHCAPZ,WSOIL,ISOIL, WUNFRZ

      !
      !Author
      !          V. Vionnet, V. Fortin, K. Rasouli (April 2020)
      !Revisions
      !
      !Object
      ! Simulate the evolution of soil freezing and thawing 
      ! using the simple heat conduction method proposed by
      ! Hayashi et al. (2007) and Mohammed et al. (2012)
      ! The upper boundary conditions are taken from the FR schemes and
      ! the coupling is done as the IFS code (see IFS techincal
      ! documentation)
      
      !
      !Arguments
      !
      !          - INPUT -
      !
      ! DT       timestep
      
      !          --- (Surface) Cover Fraction  ---
      !
      ! VEGL           fraction of LOW vegetation [0-1]
      ! VEGH           fraction of HIGH vegetation [0-1]
      ! PSN            fraction of bare ground or low veg. covered by snow [0-1]
      ! PSNVH          fraction of HIGH vegetation covered by snow [0-1]
      ! 
      !          ---  Soil thermal properties   ---
      !
      ! SOILCONDZ      soil thermal conductivity (per layer) [W K-1 m-1]
      ! SOILHCAPZ      soil heat capacity (per layer) [J m-3 K-1]
      ! TDEEP          constant deep soil temperature [K]
      ! WUNFRZ         unfrozen residual water content [m3/m3]

      !          --- Prognostic variables of SVS not modified by SOIL_FREEZING ---
      !
      ! TGRS          bare ground surface temperature from Force Restore
      ! TVEGS         surface vegetation temperature from Force Restore
      ! SNODP         snow depth for snow over bare ground/low veg
      ! SNORO         snow density for snow over bare ground/low veg
      ! TSNO          deep snow temperature for snow over bare ground/low veg
      ! SNVDP         snow depth for snow over under high veg
      ! SNVRO         snow density for snow under high veg
      ! TSNV          deep snow temperature for snow under high veg
      !
      !          - INPUT/OUTPUT  -
      !
      !          --- Prognostic variables of SVS modified by SOIL_FREEZING ---
      !
      ! TSOIL          Soil temperature (per layer) [K]
      ! WSOL (NL_SVS)    soil volumetric water content (per layer) [m3/m3]
      ! ISOL (NL_SVS)    frozen soil volumetric water (per layer) [m3/m3]
      !
      !
      !          -  DIMENSIONS  -
      !
      ! N              number of grid cells

      ! Local Variable and arrays
      INTEGER I, K


      INTEGER OPT_SNOW  ! Option to compute the heat flux between the snowpack and the soil
      INTEGER OPT_FRAC    ! Option to compute the snow cover fraction        
      INTEGER OPT_LIQWAT  ! Option to compute the unfrozen redisudal water content     
      INTEGER OPT_VEGCOND ! Option to compute the skin conductivity from the snow-free vegetation 


      REAL LAMI, CICE, DAY, MYOMEGA 
      REAL LAM_VEGL_STAB, LAM_VEGH_STAB,LAM_VEGL_UNSTAB, LAM_VEGH_UNSTAB
      REAL MFAC, RHONEW,Z0

      REAL HNET,HNETR,TTEST, TTEST2, UFWC,DFWC, FWCTEST, QLAT
      REAL RTH_GRND, RTH_SNO,RTH_SNV,FAC_SNW
      REAL, DIMENSION(N) :: HFLUX_GRND, HFLUX_SNO,HFLUX_SNV, HFLUX_VEG
      REAL, DIMENSION(N, NL_SVS+1) :: RTH, HFLUX
      REAL, DIMENSION(N, NL_SVS) :: WC, RFS, ISOILT
      REAL, DIMENSION(NL_SVS)   :: ZLAYER

      REAL, DIMENSION(N)           :: TBTM, DBTM, LAMS, LAMSV, FRAC_SNWL, FRAC_SNWH
      REAL KDIFFU,KDIFFUV 
      REAL, DIMENSION(N)           :: DAMPD,DAMPDV,LAM_VEG
      REAL, DIMENSION(N,SVS_TILESP1)           :: WTG



      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !   0. Initialize bottom temperature and depth of the bottom layer
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !

      OPT_SNOW = 2 ! Option to compute the heat flux between the snowpack and the soil 
                   ! 0: use the deep snow temperature and half the snow depth
                   ! 1: use the deep snow temperature and the full snow depth
                   ! 2: use the deep snow temp. and the max of half the snow depth
                   !     and the full snow depth minus the damping depth (Recommended) 

      OPT_FRAC = 2 ! Option to compute the snow cover fraction
                   ! 1: use a fraction = SWE/1 mm
                   ! 2: use the formulation of Niu and Yang (2007) (Recommended) 

      OPT_LIQWAT = 2 ! Option to handle unfrozen liquid water content
                   ! 1: use a constant value of 0.06 (as in VSMB)
                   ! 2: use a value that depends on soil texture (Recommended for large scale simulations) 

      OPT_VEGCOND = 1 ! Option to compute the skin conductivity for the vegetation 
                   ! 1: same value of 10 for low and high veg. in both stable and unstable conditions (Most recent version of EC Land, Boussetta et al., 2021; Recommended)
                   ! 2: different values for low and high veg. in stable and unstable conditions (See Trigo et al., JGR, 2015)


      IF(OPT_SNOW ==0) THEN
              FAC_SNW = 0.5
      ELSE IF(OPT_SNOW ==1) THEN
              FAC_SNW = 1.0
      ENDIF                   


      LAMI   = 2.22 ! Thermal conductivity of ice
      DAY     = 86400.
      CICE    = 2.106E3  ! specific heat of ice 
      MYOMEGA   = ( 2*PI )/ DAY         

      ! Option for Niu and Yang snow cover fraction
      MFAC = 1.6
      Z0 = 0.01
      RHONEW=100.0

      ! Define skin conductivity for low and high vegetation (W m-2 K-1)
      IF(OPT_VEGCOND==1) THEN 
          ! Effect of stable and unstable stratification are not taken into account 
          ! Values taken from Tab 1.2 in sup. material of Boussetta et al (2021)
          LAM_VEGH_STAB = 10 
          LAM_VEGL_STAB = 10  
          LAM_VEGH_UNSTAB = 10 
          LAM_VEGL_UNSTAB = 10  
      ELSE IF(OPT_VEGCOND ==2) THEN
          ! Effect of stable and unstable stratification are  taken into account
          ! Values taken from Tab 3 in Trigo et al. (2015)
          LAM_VEGH_STAB = 15
          LAM_VEGL_STAB = 10  
          LAM_VEGH_UNSTAB = 20 
          LAM_VEGL_UNSTAB = 10  
      ENDIF   

      ! Compute layer depth
      ZLAYER(1) =  DELZ(1)
      DO K =2, NL_SVS
        ZLAYER(K) = ZLAYER(K-1) + DELZ(K)
      ENDDO
      
      DO  I=1,N
        TBTM(I) = TDEEP(I) ! K
        DBTM(I) = ZLAYER(NL_SVS) + 0.5* DELZ(NL_SVS) ! m

         ! Snow thermal conductitivy
        LAMS(I) = LAMI * SNORO(I)**1.88
        LAMSV(I) = LAMI * SNVRO(I)**1.88

        ! Vegetation average skin conductivity
        IF(VEGL(I)+VEGH(I)> 0.) THEN
            IF(TVEGS(I) > TSOIL(I,1)) THEN ! Stable case
                 LAM_VEG(I) =(VEGL(I)*LAM_VEGL_STAB+VEGH(I)*LAM_VEGH_STAB)/(VEGL(I)+VEGH(I))
            ELSE  ! Unstable case
                 LAM_VEG(I) =(VEGL(I)*LAM_VEGL_UNSTAB+VEGH(I)*LAM_VEGH_UNSTAB)/(VEGL(I)+VEGH(I))
            ENDIF
        ELSE
            LAM_VEG(I) = 1. ! Set default value to make sure code is running           
        ENDIF

        ! Snow cover fraction used for the exchanges with the surface
        IF(OPT_FRAC==1) THEN
              FRAC_SNWL(I) =  MIN(RAUW*SNORO(I)*SNODP(I)/1.0,1.0)
              FRAC_SNWH(I) =  MIN(RAUW*SNVRO(I)*SNVDP(I)/1.0,1.0)
        ELSE
              FRAC_SNWL(I) = 0.
              FRAC_SNWH(I) = 0.
              IF(  SNODP(I)>0.) THEN
                  FRAC_SNWL(I) = TANH(SNODP(I)/(2.5*Z0*(RAUW*SNORO(I)/RHONEW)**MFAC))
              ENDIF
              IF( SNVDP(I)>0.) THEN
                  FRAC_SNWH(I) = TANH(SNVDP(I)/(2.5*Z0*(RAUW*SNVRO(I)/RHONEW)**MFAC))
              ENDIF
        ENDIF        
       
        DO K =1, NL_SVS
            IF(OPT_LIQWAT==1) THEN
                  RFS(I,K) = 0.06 ! Residual unfrozen content
            ELSE
                  RFS(I,K) = WUNFRZ(I,K) ! Residual unfrozen content
            ENDIF
            WC(I,K) = WSOIL(I,K) + ISOIL(I,K) ! Total water content
            ISOILT(I,K) = ISOIL(I,K)  ! Initialize frozen soil volumetric water (to be updated in the routine) 
        ENDDO

        IF(OPT_SNOW ==2) THEN
! 
             IF( SNODP(I)>0.) THEN

                KDIFFU =  LAMS(I) / ( CICE * RAUW*SNORO(I)) ! Thermal diffusivity (You et al., 2014)
                DAMPD(I) = SQRT(  2.0 * KDIFFU / MYOMEGA  ) !  Damping depth in m , assuming diurnal forcing dominates
             ELSE
                DAMPD(I) = 0.
             ENDIF

             IF( SNVDP(I)>0.) THEN

                KDIFFUV =  LAMSV(I) / ( CICE * RAUW*SNVRO(I)) ! Thermal diffusivity (You et al., 2014)
                DAMPDV(I) = SQRT( 2.0 * KDIFFUV / MYOMEGA  ) !  Damping depth in m , assuming diurnal forcing dominates
             ELSE
                DAMPDV(I) = 0.
             ENDIF

        ENDIF             
      ENDDO

      ! Compute weights of surface type in SVS:
      !               - snow-free bare ground WTG_2
      !               - snow-free vegetation WTG_3
      !               - snow-covered bare ground and low vegetation WTG_4
      !               - snow below high-vegetation WTG_5

      CALL WEIGHTS_SVS(VEGH, VEGL,FRAC_SNWL,FRAC_SNWH,N,WTG)

      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !     1. Compute the thermal resistances and the heat flux between
      !        adjacent layers
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !
      DO  I=1,N
        !
        ! Treatment of surface layer!
        !

        ! Upper boundary condition for snow-free bare ground
        RTH_GRND = 0.5*DELZ(1)/SOILCONDZ(I,1)  
        HFLUX_GRND(I) = (TGRS(I) - TSOIL(I,1)) / RTH_GRND

        ! Upper boundary condition for snow-free vegetation
         HFLUX_VEG(I) = (TVEGS(I) - TSOIL(I,1)) * LAM_VEG(I)              

        ! Upper boundary condition for snow over bare ground and low veg.
        IF(SNODP(I) > 0.) THEN ! Snow is present

           IF(OPT_SNOW ==0 .OR. OPT_SNOW ==1) THEN
              RTH_SNO = FAC_SNW*SNODP(I)/LAMS(I) + 0.5*DELZ(1)/SOILCONDZ(I,1)
           ELSE
              RTH_SNO = MAX(SNODP(I)/2., SNODP(I)-DAMPD(I))/LAMS(I) + 0.5*DELZ(1)/SOILCONDZ(I,1)
           ENDIF

           ! Heat flux at the snow/soil interface
           HFLUX_SNO(I) = (TSNO(I) - TSOIL(I,1)) / RTH_SNO

        ELSE ! No snow 
           HFLUX_SNO(I) = 0.
        ENDIF 

        ! Upper boundary condition for snow below high vegetation. 
        IF(SNVDP(I) > 0.) THEN ! Snow is present
                
           IF(OPT_SNOW ==0 .OR. OPT_SNOW ==1) THEN
              RTH_SNV = FAC_SNW*SNVDP(I)/LAMSV(I) + 0.5*DELZ(1)/SOILCONDZ(I,1)
           ELSE
             RTH_SNV = MAX(SNVDP(I)/2., SNVDP(I)-DAMPDV(I))/LAMSV(I) + 0.5*DELZ(1)/SOILCONDZ(I,1)
           ENDIF

           ! Heat flux at the snow/soil interface
           HFLUX_SNV(I) = (TSNV(I) - TSOIL(I,1)) / RTH_SNV
                   
        ELSE ! No snow 
           HFLUX_SNV(I) = 0.
        ENDIF 
                
        ! Compute average surface heat flux using weights for each surface tile
        HFLUX(I,1) = WTG(I,2) * HFLUX_GRND(I) + WTG(I,3) * HFLUX_VEG(I) + &
                               WTG(I,4) * HFLUX_SNO(I) + WTG(I,5) * HFLUX_SNV(I) 
        !
        !
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!               
        !
        ! Treatment of the following layers
        !
        DO K =2, NL_SVS
             RTH(I,K) = 0.5*DELZ(K-1)/SOILCONDZ(I,K-1) + 0.5*DELZ(K)/SOILCONDZ(I,K)
             HFLUX(I,K) = (TSOIL(I,K-1) - TSOIL(I,K))/ RTH(I,K)
        ENDDO
        !
        ! Treatment of the bottom layer
        ! Use thermal conductivity of the deepest SVS layer
        !
        RTH(I,NL_SVS+1) = 0.5* DELZ(NL_SVS)/ SOILCONDZ(I,NL_SVS) + (DBTM(I) - ZLAYER(NL_SVS)) / SOILCONDZ(I,NL_SVS)
        HFLUX(I,NL_SVS+1) = ( TSOIL(I,NL_SVS)- TBTM(I)) / RTH(I,NL_SVS+1)
        !
      ENDDO
      !
      !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !
      !     2. Compute the evolution of soil temperature
      !        
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !
      !
      ! 
      DO I=1, N
        DO K =1, NL_SVS
           HNET = (HFLUX(I,K)- HFLUX(I,K+1))*DT ! Heat flux received by layer K

           IF(TSOIL(I,K) - TRPL .GT. EPSILON_SVS_TK) THEN
              !TSOIL POSITIVE
                TTEST = TSOIL(I,K) + HNET/(SOILHCAPZ(I,K)*DELZ(K))
                IF(TTEST .LT. TRPL) THEN
                     UFWC = MAX(WSOIL(I,K) - RFS(I,K), 0.) !Maximum liquid water available for freezing
                     IF(UFWC>0.) THEN 
                        ! if have unfrozen water available for freezing
                        HNETR = HNET + (TSOIL(I,K)-TRPL) * SOILHCAPZ(I,K)*DELZ(K)

                        DFWC = -HNETR/(RAUW*CHLF*DELZ(K)) ! Maximum ice content that could be potentially formed
                        IF(UFWC>DFWC) THEN  !  Enough liquid water for freezing, temperature stay constant
                           ! All energy will be used to freeze water
                           ! because max created ice < max liquid water that can be frozen
                           TSOIL(I,K) = TRPL
                           ISOILT(I,K) = DFWC + ISOIL(I,K)
                        ELSE ! All available liquid water is frozen and temperature keep decreasing
                           ! Freeze all available water, and remaining energy flux will decrease temperature
                           HNETR  = HNETR +UFWC* RAUW*CHLF*DELZ(K)
                           TSOIL(I,K) =  TRPL + HNETR/(SOILHCAPZ(I,K)*DELZ(K))
                           ISOILT(I,K) = UFWC + ISOIL(I,K)
                        ENDIF
                     ELSE
                        TSOIL(I,K) = TTEST ! No enough liquid water for freezing, temperature keep decreasing. 
                     ENDIF                     
               ELSE  
                     TSOIL(I,K) = TTEST
               ENDIF

            ELSE IF( abs(TSOIL(I,K)-TRPL) .LE. EPSILON_SVS_TK) THEN
               ! TSOIL within "epsilon" of TRPL
               DFWC = -HNET/(RAUW*CHLF*DELZ(K))
               UFWC = MAX(WSOIL(I,K) - RFS(I,K) , 0.)  
               FWCTEST = ISOIL(I,K) + DFWC
               IF(FWCTEST.LE. 0.0) THEN 
                  ! Total melting of frozen content and ground heating 
                  ! with the remaining energy
                  HNETR = HNET -ISOIL(I,K) * RAUW*CHLF*DELZ(K)
                  ISOILT(I,K) = 0.0    
                  TSOIL(I,K) = TSOIL(I,K) + HNETR/(SOILHCAPZ(I,K)*DELZ(K))
               ELSE 
                  IF(DFWC.GT.UFWC) THEN
                      !Total freezing of soil layer and ground cooling
                      ! with the remaining energy
                      HNETR = HNET + UFWC * RAUW*CHLF*DELZ(K)
                      ISOILT(I,K) = ISOIL(I,K) + UFWC
                      TSOIL(I,K) = TSOIL(I,K) + HNETR/(SOILHCAPZ(I,K)*DELZ(K))
                   ELSE
                      ! layer is still partially frozen and T = 0 deg
                      ISOILT(I,K) = FWCTEST
                      TSOIL(I,K) = TRPL
                   ENDIF
                ENDIF

             ELSE  ! Soil at negative temperature

                ! Temperature that would be reached without phase change
                TTEST = TSOIL(I,K) + HNET/(SOILHCAPZ(I,K)*DELZ(K)) 

                IF(TTEST .GT. TRPL) THEN
                     !
                     ! Enough energy is brought to heat the soil to 0 deg and 
                     ! melt part of the ice if ice is present
                     !
                     IF(ISOIL(I,K)>0.) THEN 
                        ! If ice is present, compute the energy left after warming the soil
                        ! temp. to 0 degC
                        HNETR = HNET + (TSOIL(I,K)-TRPL) * SOILHCAPZ(I,K)*DELZ(K)

                        ! Maximum ice content that could be potentially melted with such amount of energy
                        DFWC = HNETR/(RAUW*CHLF*DELZ(K))

                        IF(DFWC<ISOIL(I,K)) THEN 
                            ! All energy is used to melt ice and some ice remains 
                            TSOIL(I,K) = TRPL
                            ISOILT(I,K) = ISOIL(I,K)-DFWC
                        ELSE         
                            ! All ice is melted and remaining energy is used to warm the layer above 0 degC
                            ! Remove the energy required to melt the ice 
                            HNETR  = HNETR -ISOIL(I,K)* RAUW*CHLF*DELZ(K) 
                            ! Update the temperature and the ice content
                            TSOIL(I,K) =  TRPL + HNETR/(SOILHCAPZ(I,K)*DELZ(K))
                            ISOILT(I,K) = 0. 
                        ENDIF
                     ELSE
                        TSOIL(I,K) = TTEST ! No melting of ice and no contribution from phase change  
                     ENDIF

                ELSE
                     !
                     ! The temperature remains negative 
                     ! 
                     ! Check if liquid water is present above the residual unfrozen water content
                     ! and freeze this water if it is the case. Such situation should not be encoutered at model runtime
                     ! but may be present if data assimilation has changed in an unconsistent way the soil temperature and/or water content. 
                     UFWC = MAX(WSOIL(I,K) - RFS(I,K), 0.)

                     IF(UFWC .GT. 0.) THEN
                         ! There is liquid water that can be frozen.
                         ! Compute the energy that would be released by the freezing of this amount of water 
                         QLAT  = UFWC* RAUW*CHLF*DELZ(K)
                         ! Compute the temperature that would be reached
                         TTEST2 = TTEST + QLAT/(SOILHCAPZ(I,K)*DELZ(K))

                         IF(TTEST2 .GT. TRPL) THEN 
                              ! Too much energy would be released 
                              QLAT =  (TRPL-TTEST)*SOILHCAPZ(I,K)*DELZ(K) ! Compute the energy which is actually relasead
                              ISOILT(I,K)  = ISOIL(I,K) + QLAT/(RAUW*CHLF*DELZ(K)) ! Update ice content
                              TSOIL(I,K) =TRPL
                         ELSE
                              ! All the available liquid water is melting and the temperature reamins below 0 deg 
                              ISOILT(I,K) = ISOIL(I,K) + UFWC 
                              TSOIL(I,K) = TTEST2
                         ENDIF
                     ELSE
                          ! No liquid water is available for freezing
                          ! The ice content does not change and the temperature remains negative
                          TSOIL(I,K) = TTEST  
                     ENDIF

                  ENDIF

             ENDIF

           ! Update frozen water content
           ISOIL(I,K) = ISOILT(I,K)
     
           ! Update liquid water content
           WSOIL(I,K) = WC(I,K) - ISOIL(I,K)

        ENDDO
      ENDDO



!

      END SUBROUTINE SOIL_FREEZING
