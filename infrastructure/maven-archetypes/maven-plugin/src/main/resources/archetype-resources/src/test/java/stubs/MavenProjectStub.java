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
