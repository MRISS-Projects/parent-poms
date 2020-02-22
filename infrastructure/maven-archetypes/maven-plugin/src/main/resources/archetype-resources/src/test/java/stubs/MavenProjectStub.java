package ${package}.stubs;

import org.apache.maven.model.DistributionManagement;
import org.apache.maven.model.Model;

/**
 * Stub for MavenProject.
 * <p/>
 *
 * @author <a href="mailto:marcelo.riss@gmail.com">Marcelo Riss</a>
 * @noinspection ClassNameSameAsAncestorName
 */
public class MavenProjectStub
    extends org.apache.maven.plugin.testing.stubs.MavenProjectStub
{
    public void setDistributionManagement( DistributionManagement distributionManagement )
    {
        getModel().setDistributionManagement( distributionManagement );
    }

    public Model getModel()
    {
        Model model = super.getModel();
        if ( model == null )
        {
            model = new Model();
            setModel( model );
        }
        return model;
    }

    public DistributionManagement getDistributionManagement()
    {
        return getModel().getDistributionManagement();
    }
    
}
