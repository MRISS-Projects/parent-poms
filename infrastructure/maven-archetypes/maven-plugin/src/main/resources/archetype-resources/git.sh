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
echo $PATH

echo "# Maven
target/**/*

#Eclipse 
*.project
*.classpath
*.settings
/target/
/.settings/
/.classpath/
/.project/
**/target/**/*" > .gitignore

current_dir=`pwd`
current_basename=`basename $current_dir`
echo $current_basename

cd ..

git add -A $current_basename

cd $current_basename


