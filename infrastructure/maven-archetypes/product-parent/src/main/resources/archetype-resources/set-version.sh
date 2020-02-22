mvn -N install
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N install

for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..." 
		mvn -N -DgenerateBackupPoms=false -DallowSnapshots=true -DnewVersion=$1 versions:set versions:update-parent
     fi
     cd ..
  fi
done