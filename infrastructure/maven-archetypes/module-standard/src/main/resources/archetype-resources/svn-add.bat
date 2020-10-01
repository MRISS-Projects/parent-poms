@rem ***************************************************************************
@rem Copyright 2020 Marcelo Riss
@rem
@rem Licensed under the Apache License, Version 2.0 (the "License");
@rem you may not use this file except in compliance with the License.
@rem You may obtain a copy of the License at
@rem
@rem     http://www.apache.org/licenses/LICENSE-2.0
@rem
@rem Unless required by applicable law or agreed to in writing, software
@rem distributed under the License is distributed on an "AS IS" BASIS,
@rem WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
@rem See the License for the specific language governing permissions and
@rem limitations under the License.
@rem ***************************************************************************
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