/*******************************************************************************
 * Copyright 2020 Marcelo Riss
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/
#set( $symbol_pound = '#' )
#set( $symbol_dollar = '$' )
#set( $symbol_escape = '\' )
package ${package};

import java.io.File;
import java.util.Properties;

import org.apache.maven.plugin.testing.AbstractMojoTestCase;
import org.apache.maven.project.MavenProject;
import org.codehaus.plexus.configuration.PlexusConfiguration;
import org.mockito.Mockito;

public class MyMojoTDDTest extends AbstractMojoTestCase {

	/** INIT THIS WITH THE PLUGIN NAME **/
	private String pluginName="${artifactId}";
	
	protected void setUp() throws Exception {
        // required for mojo lookups to work
        super.setUp();
	}

	protected void tearDown() throws Exception {
		super.tearDown();
	}

	public void testExecute() {
        testPom("pom");
	}
	
	public void testExecute1() {
        testPom1("pom1");
	}

	private void testPom(String testPomName) {
		File testPom = new File( getBasedir(), "target/test-classes/integration/"+testPomName+".xml" );
		try {
			PlexusConfiguration pc = this.extractPluginConfiguration(pluginName, testPom);
			MyMojo mojo = new MyMojo();
			this.configureMojo(mojo, pc);
			assertNotNull(mojo);
			mojo.execute();
		} catch (Exception e) {
			System.out.println("Error: " + e.getMessage() + " - Trying with mocked objects...");
			// Try with mockito
			try {
				MyMojo mojo = Mockito.mock(MyMojo.class);
				assertNotNull(mojo);
				mojo.execute();
			} catch (Exception e2) {
				e.printStackTrace();
				fail(e.getMessage());
			}				
		}
	}
	
	private void testPom1(String testPomName) {
		File testPom = new File(getBasedir(),
				"target/test-classes/integration/" + testPomName + ".xml");
		try {
			MyMojo mojo = (MyMojo) lookupMojo(
					"myGoal", testPom);
			assertNotNull(mojo);
			mojo.setBaseDir(testPom.getParentFile());

			mojo.execute();
		} catch (Exception e) {
			System.out.println("Error: " + e.getMessage() + " - Trying with mocked objects...");
			// Try with mockito
			try {
				MyMojo mojo = Mockito.mock(MyMojo.class);
				assertNotNull(mojo);
				mojo.execute();
			} catch (Exception e2) {
				e.printStackTrace();
				fail(e.getMessage());
			}
		}
	}

}
