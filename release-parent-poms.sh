
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd infrastructure
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1-SNAPSHOT versions:set
mvn -N -P release-prepare generate-sources
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd skins
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false versions:update-child-modules
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd ../announcement-templates
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false versions:update-child-modules
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd ../maven-archetypes
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false versions:update-child-modules
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd ../maven-plugins
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false versions:update-child-modules
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

cd ../../framework
mvn -N -DgenerateBackupPoms=false versions:update-parent
mvn -N -DgenerateBackupPoms=false -DnewVersion=$1 versions:set
mvn -N -Prelease-deployment deploy
mvn -N -Prelease-deployment -Dsite.deployment.personal.main=$3 site-deploy
mvn -N -DgenerateBackupPoms=false versions:update-child-modules
mvn -N -DgenerateBackupPoms=false -DnewVersion=$2 versions:set
mvn -N -Dmessage="New parent pom version $2" scm:checkin

