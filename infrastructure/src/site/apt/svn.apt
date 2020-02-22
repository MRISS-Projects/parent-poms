
Subversion

* Table of Contents

%{toc|section=1|fromDepth=2|toDepth=3}

* SVN Client

** Linux

 The instructions are compatible with Ubuntu 14.04.
 Open a command prompt and run the command:
 
+-------------------------+
sudo apt-get install subversion
+-------------------------+
 
 Enter your administration password. Answer Y for all questions.
 
*** Configuring the Digital Certificate

 [[1]] You should have created and exported a certificate to a PFX file inside
       the user home folder (or any sub-folder inside it).
       See details about certificate creation at {{{./dev-FAQ.html}this FAQ}}.
 
 [[2]] Certify that the folder <<<$HOME/.subversion>>> exists and the file named 
 <<servers>> inside this folder exists.
 
 [[3]] Edit this file, and find the <<groups>> section. Insert a group like:
 
+----------------+
[groups]
teamforge = 
+----------------+

 [[4]] Create a new group section with the named <<teamforge>> group just below the 
 groups section. Place the certificate information there. The file should look 
 like:
 
+-----------------+
[groups]
teamforge = 

[teamforge]
http-compression = yes
ssl-client-cert-file = /path/to/your/certificate/class-b-certificate.pfx
ssl-client-cert-password = YOUR_PASSWORD (the one you have used to export the cerfificate from the browser to a file)
+-----------------+

*** Configuring Proxy

 [[1]] In the same file named <<<$HOME/.subversion/servers>>>, add the proxy
 information to the <<teamforge>> group. The file should then look like the
 following:
 
+-----------------+
[groups]
teamforge = 

[teamforge]
http-proxy-host = 
http-proxy-port = 
http-compression = yes
ssl-client-cert-file = /path/to/your/certificate/class-b-certificate.pfx
ssl-client-cert-password = YOUR_PASSWORD (the one you have used to export the cerfificate from the browser to a file)
+------------------+
  
*** Avoiding password storage in new Ubuntu versions

 In some new ubuntu distros, GNU keyring will be turned on by default. This will
 let your svn connections to fail, even if you have the right certificate, 
 unless you configure ubuntu/gnu keyring system to operate with svn. The short 
 path to avoid that is to completely disable the GNU keyring system. 
 I order to do that, do the following:

 [[1]] Edit the file <<<$HOME/.subversion/config>>>

 [[2]] Insert the a new line with contents <<<password-stores =>>> (yes, just let 
       the line empty after the equals sign :-). Possibly this section already 
       exists and just need to be uncommented and have your contents changed. 
       (see  
       {{{http://old.nabble.com/disable-warning-about-gnome-keyring--td23506009.html}this link}} 
       for an explanation).

 [[3]] Save the file.

 [[4]] Try to invoke any svn command at command line (assuming that you have 
       correctly configured the digital certificates the command should work).
 
**  Windows

 Install  {{{http://tortoisesvn.tigris.org/}tortoise svn client}}. Install  
 {{{http://www.sliksvn.com/en/download}windows command line client}}. 
 
 In case of Tortoise SVN, the client should ask for the digital certificate and
 password to unlock it using its UI at the moment of checkout.
 
 The command line utility is optional. It will demands digital certificates and
 proxy configuration follwing the same instructions for linux, above. However,
 the place where the file named <<servers>> is located might be different, 
 depending on the operational system:

 * In windows vista, the file called <<servers>> should be placed at: 
   <<<C:\ProgramData\Subversion>>>. Usually this folder is hidden, so you may 
   need to enable it to be shown in windows explorer.
   
 * In windows XP, the file called <<servers>> should be placed at: 
   <<<%HOMEPATH%\Subversion>>>.    
   
 * In Windows 7/8.1, the file called <<servers>> should already exists, when
   the subversion client is installed, at:
   <<<C:\Users\[YOUR_USER]\AppData\Roaming\Subversion>>>.
   
 * For other systems check the command line utility documentation. Additionally,
   you can check the subversion section at {{{./dev-FAQ.html}this FAQ}}.
    
** Checking out the project

*** Before Checking out

 If you intent to use subclipse plugin inside eclipse, you can jump the next
 two sections and wait till you configure eclipse at the {{{./eclipse.html}eclipse section}}.
 Just take care of following the rigth order, which will demand you to install
 maven and tomcat prior eclipse. See the right order {{{./setup.html}here}}.
 
*** Full Checkout

 In order to execute a full checkout, use your pre-configured SVN client and
 execute a checkout at the address:
 
+---------------------+
+---------------------+

*** Partial Checkout per Product

 Go to {{{}products home address}}
 and click on a product at the <<Modules>> section at the left menu.
 
 After that, at the left menu of the selected product, you go to
 <<Project Documentation -> Project Information -> Source Repository>>. There
 you will find specific information about the source code address for an
 specific product.
 
 