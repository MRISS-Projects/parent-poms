
Writing Projects Documenation

* Table of Contents

%{toc|section=1|fromDepth=2|toDepth=3}

* Standard Folder Structure

 All maven modules have the same structure regarding documentation:
 
 * <<<src/site/apt>>> - It has files in APT (Almost Plain Text) format which will 
   describe the documentation.
   
 * <<<src/site/site.xml>>> - It has the main left menu structure to be presented in 
   all HTML pages of the documentation.
   
 * <<<src/site/resources/images>>> - It has all the images used as references inside
   the documentation.
   
 * <<<src/site/fml>>> - It has the faq.fml file written in the specific FML
   (FAQ Markup Language) format.

* Adding Items to the Main Menu

 Edit the file <<<src/site/site.xml>>> and edit menu contents, using the following 
 syntax.
 
+-----------+
<project>
  ...
  <body>
    ...
    <menu name="Overview">
      <item name="Foo" href="foo.html" />
      <item name="FAQ" href="faq.html" />
    </menu>
    ...
  </body>
  ...
</project>
+-----------+

 The <<<href>>> item may also point to external links or sites. For each local
 html item you reference in this file, you need to create the equivalent <<<.apt>>> 
 file at the <<<src/site/apt>>> folder or <<<src/site/fml>>> folder. So, if you 
 have referenced <<<foo.html>>> and <<<faq.html>>> you need to create
 <<<src/site/apt/foo.apt>>> and <<<src/site/fml/faq.fml>>>.

* The APT Format

 The full reference for the APT format is found {{{http://maven.apache.org/doxia/references/apt-format.html}here}}.
 
* Writing Documentation Using APT Editor

 When you open an <<<.apt>>> file, eclipse will open it at the APT editor. This
 editor has two sub-tabs bellow the editing window: <<View>> and <<Edit>>. The
 Edit tab will allow you enter the content. The View tab will show you a preview
 or your text, allowing to you to test the text you are writing.
 
[images/apt-editor-edit.png]

[images/apt-editor-view.png]

* Writing FAQs

 The full reference for the FAQ format can be found 
 {{{http://maven.apache.org/doxia/references/fml-format.html}here}}.
 
 You need to edit or create files with <<<.fml>>> extension at the folder
 <<<src/site/fml>>> for the modules you want FAQs. After creating the files, 
 you can reference them at the <<<src/site/site.xml>>> using the html extension.

* References to Other Resources

 Images are place under src/site/resources/images, but are referenced using their
 file names just as relative locations to the <<<images>>> folder. Thus, you
 will also reference images using <<<images/my-image-name.png>>>, for example,
 just like:
 
+--------------------+
[images/test-image.png]
+--------------------+

* Testing the Documentation Using Maven

 You can find a <<<maven-site.sh>>> file at the root folder of each module
 allowing to test the site generation. The generated site will be at the folder
 <<<target/site>>> relative to the root of the maven module.
 
 When the module is a parent, all children will also have their site generated, 
 and you need to go down in the structure for each <<<target/site>>> inside
 each module.
 
 If you are at windows, look at the .sh file for the correct mvn command line
 to invoke to execute a mvn site generation.
 
* Testing the Documentation Deployment Using Maven

 You can find a <<<maven-site-deploy.sh>>> file at the root folder of each module
 allowing to test the site deployment. If you have propertly configured maven,
 the site will be deployed at <<<c:\tmp\sites\snapshots>>> at windows, or
 <<</tmp/sites/snapshots>>> at linux.

 If you are at windows, look at the .sh file for the correct mvn command line
 to invoke to execute a mvn site deployment.