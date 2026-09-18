# Maven

## Contents

* [Installing](#Installing)
* [Configuring](#Configuring)
* [Running](#Running)

## Installing

1. Download maven **3.9.9** from
   [https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip](https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip)

2. Unzip it on a folder of your preference

3. Set environment variables.

    1. Linux

        1. Put it at your `$HOME/.profile` file

           ```bash
           export M2_HOME=/path/to/where/you/extracted/maven/apache-maven-3.9.9
           export PATH=$M2_HOME/bin:$PATH
           export MAVEN_OPTS='-Xmx1024m'
           ```

        2. If you already have java set up, your `.profile`, it
           should look like this:

           ```bash
           export JAVA_HOME=/your/jdk/parent/folder/java
           export M2_HOME=/path/to/where/you/extracted/maven/apache-maven-3.9.9
           export PATH=$JAVA_HOME/bin:$M2_HOME/bin:$PATH
           export MAVEN_OPTS='-Xmx1024m'
           ```

        3. Logout and login again.

        4. Test by opening a terminal and typing:

           ```bash
           mvn -version
           ```

        5. The result should be similar to:

           ```text
           Apache Maven 3.9.9 (8e8579a9e76f7d015ee5ec7bfcdc97d260186937)
           Maven home: /home/[YOUR_USER]/apps/apache-maven-3.9.9
           Java version: 17.0.20.1, vendor: Eclipse Adoptium, runtime: /home/[YOUR_USER]/apps/jdk-17.0.20.1+1
           Default locale: en_US, platform encoding: UTF-8
           OS name: "linux", version: "6.8.0-45-generic", arch: "amd64", family: "unix"
           ```

    2. Windows

        1. Open Control Panel go to System, Advanced system settings,
           **Environment Variables** button.

        2. At the System Variables section, click New.

        3. Set `M2_HOME` and point to the root of maven folder.

        4. Search for the variable `Path` in the list, click on it and press Edit.

        5. Put the maven bin folder right after java home:

           ```text
           %JAVA_HOME%\bin;%M2_HOME%\bin;
           ```

        6. Set the variable MAVEN_OPTS.

           ```text
           MAVEN_OPTS=-Xmx1024m
           ```

        7. The result should be similar to:

           ```text
           Apache Maven 3.9.9 (8e8579a9e76f7d015ee5ec7bfcdc97d260186937)
           Maven home: C:\data\apache-maven-3.9.9
           Java version: 17.0.20.1, vendor: Eclipse Adoptium, runtime: C:\Program Files\Eclipse Adoptium\jdk-17.0.20.1+1
           Default locale: en_US, platform encoding: Cp1252
           OS name: "windows 11", version: "10.0", arch: "amd64", family: "windows"
           ```

## Configuring

### Copying settings.xml

1. If you already have executed a full checkout, get the file at
   `production/global-settings.xml` in your working copy and copy to
   `M2_HOME/conf`. If you have not executed a full checkout, get
   a copy of global settings here.

2. Rename the file `settings.xml` already located at `M2_HOME/conf`
   to `settings.old.xml`.

3. Rename the previously copied `global-settings.xml` at
   `M2_HOME/conf` to `settings.xml`.

4. If you already have executed a full checkout, get the file at
   `production/infrastructure/tools/user-settings.xml` in your working copy and copy to
   `$HOME/.m2` at linux or `C:\Users\YOUR_USER\.m2` at windows. If
   folder `.m2` does not exist at that destination, please create the
   folder. If you have not executed a full checkout, get
   a copy of user settings here.

5. Rename the file `settings.xml` already located at `.m2` folder,
   if there already is one, to `settings.old.xml`.

6. Rename the previously copied `user-settings.xml` at
   `.m2` folder to `settings.xml`.

### Configuring Proxy

The proxy for maven connections doesn't really need to be configured, since
it should be present at M2_HOME/conf/settings.xml. You just need to open this
file and check if the proxy address is set

## Running

If you already have executed a full checkout:

1. Start tomcat.

2. Open a command prompt and go to the `production` folder.

    1. If desired, this can be run only for a particular product. In this case
       You need to go to **production/products/YOUR_PRODUCT**.

    2. If only 1 product was checked out using subversion, then you run
       the maven command at the root of the checkouted project.

3. Type:

   ```bash
   mvn -DskipTests clean install
   ```

4. The build will take some time and during the first time you run,
   maven will take some time to download all dependencies to the folder
   `YOUR_HOME/.m2/repository`, where YOUR_HOME is `$HOME` for linux or
   `C:\Users\YOUR_USER` at windows. This will be executed only at the
   first time and subsequent execution will not require download again.

5. Wait till maven finishes with a SUCCESSFUL BUILD message.

If you did not execute the full checkout, you will need to bookmark this section
and back to it after you checkout using eclipse subclipse plugin.
