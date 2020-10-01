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
import java.util.List;

import org.apache.maven.doxia.siterenderer.Renderer;
import org.apache.maven.doxia.tools.SiteTool;
import org.apache.maven.execution.MavenSession;
import org.apache.maven.model.Dependency;
import org.apache.maven.model.Repository;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugin.MojoFailureException;
import org.apache.maven.plugin.logging.Log;
import org.apache.maven.plugins.annotations.Component;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProjectBuilder;
import org.apache.maven.settings.Settings;
import org.codehaus.plexus.i18n.I18N;

/**
 * Mojo base class for all goals.
 * 
 * @since 1.0.0
 */
public class BaseMojo extends AbstractMojo {
	
	// ----------------------------------------------------------------------
	// Mojo components
	// ----------------------------------------------------------------------

	/**
	 * SiteTool component.
	 *
	 * @since 1.0.2
	 */
	@Component
	protected SiteTool siteTool;

	/**
	 * Doxia Site Renderer component.
	 */
	@Component
	protected Renderer siteRenderer;
	
	/**
	 * Artifact resolver.
	 * 
	 * @since 1.0.0
	 */
	@Component
	protected org.apache.maven.artifact.resolver.ArtifactResolver resolver;
	
	/**
	 * Artifact factory.
	 * 
	 * @since 1.0.0
	 */
	@Component
	protected org.apache.maven.artifact.factory.ArtifactFactory artifactFactory;
	
	/**
	 * Maven project builder.
	 * 
	 * @since 1.0.0
	 */
	@Component
	protected MavenProjectBuilder mavenProjectBuilder;	

	/**
	 * Internationalization component, could support also custom bundle using
	 * {@link #customBundle}.
	 */
	@Component
	private I18N i18n;

	// ----------------------------------------------------------------------
	// Mojo parameters
	// ----------------------------------------------------------------------

	/**
	 * The Maven Session.
	 *
	 * @since 1.0.2
	 */
	@Parameter (defaultValue = "${session}", readonly = true)
	protected MavenSession mavenSession;	
	
	/**
	 * List of project dependencies
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property="project.dependencies")
	protected List<Dependency> projectDependencies;

	/**
	 * Local repository.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property = "localRepository", required = true, readonly = true)
	protected org.apache.maven.artifact.repository.ArtifactRepository localRepository;

	/**
	 * Maven project.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(defaultValue = "${project}", readonly = true, required = true)
	protected org.apache.maven.project.MavenProject mavenProject;

	/**
	 * The output directory for the report. Note that this parameter is only
	 * evaluated if the goal is run directly from the command line. If the goal
	 * is run indirectly as part of a site generation, the output directory
	 * configured in the Maven Site Plugin is used instead.
	 */
	@Parameter(property = "project.reporting.outputDirectory", required = true)
	protected File outputDirectory;	

	/**
	 * Remote repositories.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property = "project.remoteArtifactRepositories")
	protected List<Repository> remoteRepositories;

	/**
	 * Target directory.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property="project.build.directory")
	protected String targetDirectory;

	/**
	 * Target classes directory.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property="project.build.outputDirectory")
	protected String targetClassesDirectory;

	/**
	 * Artifact Id.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property="project.artifactId")
	protected String artifactId;
	
	/**
	 * Version.
	 * 
	 * @since 1.0.0
	 */
	@Parameter(property="project.version")
	protected String version;	
	
    /**
     * Settings.
     * 
     * @since 1.0.0
     */
	@Parameter(defaultValue = "${settings}", readonly = true, required = true)
    protected Settings settings;		

    /**
     * Log.
     * 
     * @since 1.0.0
     */
	protected Log log;
	
	/**
	 * Debug
	 * 
	 * @since 1.0.0
	 */
	@Parameter(defaultValue = "false")
	protected boolean debug = false;
	
    /**
     * Base dir
     * 
     * @since 1.0.0
     */
	@Parameter(property = "basedir", required = true)
    protected File basedir;
	
	/**
	 * If is to show information messages or not during the mojos execution
	 * 
	 * @since 1.0.0
	 */
	@Parameter(defaultValue = "false")
	protected boolean echo;

	public void execute() throws MojoExecutionException, MojoFailureException {
		this.log = getLog();
	}

	public List<Dependency> getProjectDependencies() {
		return projectDependencies;
	}

	public org.apache.maven.artifact.resolver.ArtifactResolver getResolver() {
		return resolver;
	}

	public org.apache.maven.artifact.repository.ArtifactRepository getLocalRepository() {
		return localRepository;
	}

	public org.apache.maven.project.MavenProject getMavenProject() {
		return mavenProject;
	}

	public org.apache.maven.artifact.factory.ArtifactFactory getArtifactFactory() {
		return artifactFactory;
	}

	public List<Repository> getRemoteRepositories() {
		return remoteRepositories;
	}

	public MavenProjectBuilder getMavenProjectBuilder() {
		return mavenProjectBuilder;
	}

	public String getTargetDirectory() {
		return targetDirectory;
	}

	public String getTargetClassesDirectory() {
		return targetClassesDirectory;
	}

	public String getArtifactId() {
		return artifactId;
	}

	public String getVersion() {
		return version;
	}

	public void setBaseDir(File baseDir) {
		this.basedir = baseDir;
	}
	
}
