#set( $symbol_pound = '#' )
#set( $symbol_dollar = '$' )
#set( $symbol_escape = '\' )
package ${package};

import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugin.MojoFailureException;

/**
 * This is my mojo
 * 
 * @goal myGoal
 * 
 * @since 1.0.0
 */
public class MyMojo
    extends BaseMojo
{

	public MyMojo() {
		
	}	

	public void execute()
        throws MojoExecutionException, MojoFailureException
    {
    	super.execute();
	
    }

}

