#!/bin/sh
current_dir=`pwd`
current_basename=`basename $current_dir`
echo $current_basename
cd ..
svn add $current_basename
cd $current_basename
svn -R propset svn:ignore 'target
.settings
.classpath
.project' .