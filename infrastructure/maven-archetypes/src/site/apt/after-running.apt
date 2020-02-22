
After Running an Archetype

 After running an Archetype, it is recommended the manual execution of the
 following steps:
 
  * Remove ant-run <<<plugin>>> section which is running svn add command after
    project creation. Remove svn-add.sh and svn-add.bat scripts. 
    
  * Replace the information at the <<name>> and <<description>> sections inside
    the pom.xml file.
    
  * Update property <<<announcement.introduction>>> accordingly.
  
  * Remove/edit the <<<announcement.list>>> property. Removal is recommended
    if you want to use the parent's announcement list.
    
  * Update <<<group.id.path>>> property. If a new sub-product was created
    and will be released independently, the value of this project should 
    be prepended with <<<products/>>>.
    
  * Adjust property <<<jenkins.view>>> accordingly.
  
  * Create a jenkins job under the jenkins view with name [project.artifactId]-Snapshot, having the snapshot deployment profile configured to store
    zip distribution file.  
    
  * Remove unnecessary files. This is needed only if you ran the 
    module-standard archetype and set the packaging to pom. In this case, 
    the module will be a parent module. Thus, all files under <<src/main/java, 
    src/man/resources, src/test/java and src/test/resources>> can be discarded.
    
  * Edit the file <<src/site/apt/index.apt>> to reflect a small introduction or
    description about the new module recently created.
    
  * Edit and change the <<developers>> section inside pom.xml.
  
  * Edit and change the order of the <<modules>> section of the newly created
    module parent module according with you plans of dependency. Modules which
    will be dependencies of other brother modules should came first in the order
    so that they can be build first.
    
  * Edit file <<src/site/apt/releases-history.apt>> to update the link pointing to
    the site with releases history. Valid for product parent archetypes and
    maven plugins.
    
  * For projects using trac as issue tracker, update property 
    <<<trac.release.history.number>>> with the report number used to grab the list of
    issues closed by each release (releases history).
    