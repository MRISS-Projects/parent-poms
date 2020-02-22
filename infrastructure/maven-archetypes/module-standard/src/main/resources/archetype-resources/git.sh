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


