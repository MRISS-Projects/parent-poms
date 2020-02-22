mvn -N install

cd infrastructure
mvn -N install

cd announcement-templates
mvn -N install
for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..."
		mvn -N install
     fi
     cd ..
  fi
done

cd ../maven-archetypes
mvn -N install
for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..."
		mvn -N install
     fi
     cd ..
  fi
done

cd ../maven-plugins
mvn -N install
for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..."
		mvn -N install
     fi
     cd ..
  fi
done

cd ../skins
mvn -N install
for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..."
		mvn -N install
     fi
     cd ..
  fi
done

cd ../../framework
mvn -N install

cd ../products
mvn -N install

for dir in `ls`
do
  if [ -d "$dir" ]; then
     echo "Entering directory $dir..."
     cd $dir
     if [ -e "pom.xml" ]; then
		echo "Entered product dir $dir. Running maven to update parent section..."
		mvn -N install
     fi
     cd ..
  fi
done

