AC_INIT([Parafly], [0.1], [bug-report@address])
AM_INIT_AUTOMAKE([foreign -Wall -Werror])
AC_LANG([C++])
AC_PROG_CXX
# AC_OPENMP compiles its probe with LDFLAGS, so -fopenmp there (as conda
# builds set it) reads as "none needed" while the real compiles, which do not
# see LDFLAGS, get no OpenMP: ParaFly then runs its commands one at a time.
save_LDFLAGS="$LDFLAGS"
LDFLAGS=""
AC_OPENMP
LDFLAGS="$save_LDFLAGS"
AC_SUBST([AM_CXXFLAGS], ["-m64 $OPENMP_CXXFLAGS"])
case $CXX in
  g++*) AC_SUBST([AM_CXXFLAGS],["-pedantic -Wall -Wextra -Wno-long-long -Wno-deprecated $AM_CXXFLAGS"]);;
  sunCC*) AC_SUBST([AM_CXXFLAGS], ["-library=stlport4 -xopenmp -xvpara -fast $AM_CXXFLAGS"]) ;;
  icpc*) AC_SUBST([AM_CXXFLAGS], ["-Wall -openmp $AM_CXXFLAGS"]) ;;
esac
AC_SEARCH_LIBS([cos], [m])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile src/Makefile])
AC_OUTPUT
