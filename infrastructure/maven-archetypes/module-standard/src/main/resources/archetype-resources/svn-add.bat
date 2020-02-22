@echo off
set current_dir=%~dp0
set MYDIR1=%current_dir:~0,-1%

for %%f in (%MYDIR1%) do set current_basename=%%~nxf
echo %current_basename% 

cd ..
svn add %current_basename%

cd %current_basename%
echo .settings> .svnignore
echo .classpath>> .svnignore
echo .project>> .svnignore
echo target>> .svnignore 
svn propset svn:ignore -F .svnignore . 
del .svnignore