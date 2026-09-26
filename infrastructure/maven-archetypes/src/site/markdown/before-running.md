
Before Running an Archetype

 Before running an archetype command:
 
 [[1]] check if you have placed the file at
       {{{http:///archetypes-catalog/archetype-catalog.xml}http:///archetypes-catalog/archetype-catalog.xml}}
       into the folder <<~/.m2 (linux)>> or <<%USERPROFILE%\.m2 (windows)>>.
       
 [[2]] check if your settings.xml file at [MAVEN_HOME]/conf has the following repository:
 
+----------------------------+
<repository>
	<id>archetype</id>
	<url>http:///archetypes-catalog</url>
	<releases>
		<enabled>true</enabled>
		<updatePolicy>daily</updatePolicy>
		<checksumPolicy>warn</checksumPolicy>
	</releases>
	<snapshots>
		<enabled>false</enabled>
		<updatePolicy>daily</updatePolicy>
		<checksumPolicy>warn</checksumPolicy>
	</snapshots>
</repository>	
+----------------------------+