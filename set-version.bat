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
@rem Usage: set-version.bat <newVersion>
@rem Example: set-version.bat 3.9.0-SNAPSHOT
@echo off
setlocal

if "%~1"=="" (
	echo Usage: set-version.bat ^<newVersion^>
	exit /b 1
)

set "NEW_VERSION=%~1"

call :get_current_version "infrastructure\skins\company-skin\pom.xml" COMPANY_SKIN_VERSION
call :get_current_version "infrastructure\skins\product-module-skin\pom.xml" PRODUCT_MODULE_SKIN_VERSION
call :get_current_version "infrastructure\skins\products-skin\pom.xml" PRODUCTS_SKIN_VERSION
call :get_current_version "infrastructure\announcement-templates\default-announcement-template\pom.xml" DEFAULT_ANNOUNCEMENT_TEMPLATE_VERSION
call :get_current_version "infrastructure\maven-archetypes\maven-plugin\pom.xml" MAVEN_PLUGIN_ARCHETYPE_VERSION
call :get_current_version "infrastructure\maven-archetypes\module-standard\pom.xml" MODULE_STANDARD_ARCHETYPE_VERSION
call :get_current_version "infrastructure\maven-archetypes\product-parent\pom.xml" PRODUCT_PARENT_ARCHETYPE_VERSION

set "EXTRA_ARGS="
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.skins:company-skin=%COMPANY_SKIN_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.skins:company-skin=%COMPANY_SKIN_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.skins:product-module-skin=%PRODUCT_MODULE_SKIN_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.skins:product-module-skin=%PRODUCT_MODULE_SKIN_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.skins:products-skin=%PRODUCTS_SKIN_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.skins:products-skin=%PRODUCTS_SKIN_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.announcement-templates:default-announcement-template=%DEFAULT_ANNOUNCEMENT_TEMPLATE_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.announcement-templates:default-announcement-template=%DEFAULT_ANNOUNCEMENT_TEMPLATE_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.maven-archetypes:maven-plugin=%MAVEN_PLUGIN_ARCHETYPE_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.maven-archetypes:maven-plugin=%MAVEN_PLUGIN_ARCHETYPE_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.maven-archetypes:module-standard=%MODULE_STANDARD_ARCHETYPE_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.maven-archetypes:module-standard=%MODULE_STANDARD_ARCHETYPE_VERSION%"
set "EXTRA_ARGS=%EXTRA_ARGS% -Dproject.rel.com.mriss.mriss-parent.infrastructure.maven-archetypes:product-parent=%PRODUCT_PARENT_ARCHETYPE_VERSION% -Dproject.dev.com.mriss.mriss-parent.infrastructure.maven-archetypes:product-parent=%PRODUCT_PARENT_ARCHETYPE_VERSION%"

call mvn -B -DautoVersionSubmodules=true -Dproject.dev.com.mriss:mriss-parent=%NEW_VERSION% %EXTRA_ARGS% release:update-versions
exit /b %errorlevel%

:get_current_version
setlocal
set "POM_FILE=%~1"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$content = Get-Content -Raw '%POM_FILE%'; if ($content -match '<version>([^<]+)</version>') { $matches[1] }"`) do set "MODULE_VERSION=%%V"
if not defined MODULE_VERSION (
	echo Could not read version from %POM_FILE%
	endlocal & exit /b 1
)
endlocal & set "%~2=%MODULE_VERSION%"
exit /b 0
