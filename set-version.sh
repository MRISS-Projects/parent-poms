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
mvn -B -Dline.separator=$'\n' -DautoVersionSubmodules=true -Dproject.dev.com.mriss:mriss-parent=$1 release:update-versions

