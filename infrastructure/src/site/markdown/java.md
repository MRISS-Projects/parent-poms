# Installing Java

## Contents

* [Download and Installation](#Download_and_Installation)
* [Setting environment variables](#Setting_environment_variables)
* [Verifying the installation](#Verifying_the_installation)

## Download and Installation

If you are using a PCCOE version of windows, you will possibly have JRE 1.5, 1.6, 1.7 or
1.8 installed. In this case it is recommended to uninstall it, before to start
the process of installation of a new JDK. Use the **Application Self-Service
Manager** to find and remove the JRE already installed. After that, follow
the steps:

1. Download an Eclipse Temurin JDK 17 from
   [https://adoptium.net/temurin/releases/?version=17](https://adoptium.net/temurin/releases/?version=17).

    1. **IMPORTANT NOTE**: Download and install a **JDK, not a JRE**. On the
       download page select Version **17 (LTS)**, your operating system and
       architecture, and the **JDK** package type.

2. Windows

    1. There should be a .exe windows installer. Just follow the
       instructions.

3. Linux

    1. Download the .tar.gz file. After downloading it, uncompress it at
       a folder of your preference.

    2. Create a link. Open a command prompt, go to the jdk parent folder
       (the folder where you extract jdk into), and type:

       ```bash
       ln -s jdk-17.0.X+Y java (where X and Y match the release you downloaded)
       ```

## Setting environment variables

### Linux

1. Open the file `/home/[YOUR_USER]/.profile`. This file might be hidden.
   If it does not appear at your home folder, using the file explorer, type
   `Ctrl+h`. Go to the end of the file and add:

   ```bash
   export JAVA_HOME=/your/jdk/parent/folder
   export PATH=$JAVA_HOME/bin:$PATH
   ```

### Windows

1. Open Control Panel go to System, Advanced system settings, **Environment
   Variables** button.

2. At the System Variables section, click New.

3. Set JAVA_HOME and point to the root of jdk folder.

4. Search for the variable named **Path** in the list, click on it and press
   Edit.

5. Prepend the value with:

   ```text
   %JAVA_HOME%\bin;
   ```

## Verifying the installation

1. Open a command prompt and type:

   ```bash
   java -version
   ```

2. The result should be something like:

   ```text
   openjdk version "17.0.20.1" 2026-08-18
   OpenJDK Runtime Environment Temurin-17.0.20.1+1 (build 17.0.20.1+1)
   OpenJDK 64-Bit Server VM Temurin-17.0.20.1+1 (build 17.0.20.1+1, mixed mode, sharing)
   ```
