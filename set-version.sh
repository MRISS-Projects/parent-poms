#!/bin/sh
#*******************************************************************************
# Copyright 2020 Marcelo Riss
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#*******************************************************************************
# Usage: ./set-version.sh <newVersion>
# Example: ./set-version.sh 3.9.0-SNAPSHOT

set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: ./set-version.sh <newVersion>"
	exit 1
fi

new_version="$1"

get_current_version() {
	awk 'match($0, /<version>([^<]+)<\/version>/, v) { print v[1]; exit }' "$1"
}

set -- mvn -B -Dline.separator=$'\n' -DautoVersionSubmodules=true "-Dproject.dev.com.mriss:mriss-parent=${new_version}"

for static_module in \
	"com.mriss.mriss-parent.infrastructure.skins:company-skin|infrastructure/skins/company-skin/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.skins:product-module-skin|infrastructure/skins/product-module-skin/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.skins:products-skin|infrastructure/skins/products-skin/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.announcement-templates:default-announcement-template|infrastructure/announcement-templates/default-announcement-template/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.maven-archetypes:maven-plugin|infrastructure/maven-archetypes/maven-plugin/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.maven-archetypes:module-standard|infrastructure/maven-archetypes/module-standard/pom.xml" \
	"com.mriss.mriss-parent.infrastructure.maven-archetypes:product-parent|infrastructure/maven-archetypes/product-parent/pom.xml"
do
	module_ga="${static_module%%|*}"
	module_pom="${static_module#*|}"
	module_version="$(get_current_version "${module_pom}")"
	set -- "$@" "-Dproject.rel.${module_ga}=${module_version}" "-Dproject.dev.${module_ga}=${module_version}"
done

set -- "$@" release:update-versions
"$@"

