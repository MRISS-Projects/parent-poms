
Tomcat

* Table of Contents

%{toc|section=1|fromDepth=2|toDepth=3}

* Installing

** Linux

 [[1]] Download zip file for Tomcat 8 from {{{http://tomcat.apache.org/download-80.cgi}
       http://tomcat.apache.org/download-80.cgi}}. Donwload the zip or tar.gz
       distribution.
 
 [[2]] Extract it on a folder. 
 
 [[3]] Use the scripts at the <<<bin>>> folder to startup (<<<./startup.sh>>>) or
       shutdown (<<<./shutdown.sh>>>).
       
 [[4]] Tomcat will only work if you correctly have installed java and set
       <<<JAVA_HOME>>> variable to point to the root JDK (Java Development Kit)
       installation.

** Windows

 [[1]] Download the <<32-bit/64-bit Windows Service Installer>> for Tomcat 8 from 
       {{{http://tomcat.apache.org/download-80.cgi}http://tomcat.apache.org/download-80.cgi}}.
       
 [[2]] Run the installer. It will install a small icon to start and stop 
       tomcat at the tray icon. Additionally, a windows service will be installed, 
       and can be reached using the Windows Control Panel -> Administrative Tools ->
       Services. The service name will be <<Apache Tomcat 8.0 Tomcat8>>.
 
* Configuring User Roles

 If you already have checked out the full code base, you can go to your local
 SVN working copy at folder <<<infrastructure/tools/tomcat/conf>>> and copy the
 file <<<tomcat-users.xml>>> to the <<<conf>>> folder which should be under 
 the tomcat folder where you extracted tomcat zip file (tomcat home).
 
 If you don't have checked out the full code base, pickup this file 
 {{{}here}}.
 
* Testing Tomcat Manager Access

 [[1]] Start tomcat. At windows using the tray icon. Click with the right button
       and use the <<<Start Service>>> option. At
       Linux, open a terminal, go to the <<<TOMCAT_HOME/bin>>> and run <<<./startup.sh>>>.
       
 [[2]] Open your web browser and go to the address <<<http://localhost:8080>>>.
 
 [[3]] Click at the button <<Manager App>>. Enter the user <<tomcat>>, 
       password <<s3cret>>. You should see the tomcat manager main page.