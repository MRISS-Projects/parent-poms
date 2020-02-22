package ${package}.stubs;

import org.apache.maven.artifact.handler.ArtifactHandler;
import org.apache.maven.artifact.versioning.VersionRange;
import org.apache.maven.plugin.testing.stubs.ArtifactStub;


public class MyPluginArtifactStub
    extends ArtifactStub
{
    private String groupId;

    private String artifactId;

    private String version;

    private String packaging;

    private VersionRange versionRange;

    private ArtifactHandler handler;

    /**
     * @param groupId
     * @param artifactId
     * @param version
     * @param packaging
     */
    public MyPluginArtifactStub( String groupId, String artifactId, String version, String packaging )
    {
        this.groupId = groupId;
        this.artifactId = artifactId;
        this.version = version;
        this.packaging = packaging;
        versionRange = VersionRange.createFromVersion( version );
    }

    @Override
    public void setGroupId( String groupId )
    {
        this.groupId = groupId;
    }

    @Override
    public String getGroupId()
    {
        return groupId;
    }

    @Override
    public void setArtifactId( String artifactId )
    {
        this.artifactId = artifactId;
    }

    @Override
    public String getArtifactId()
    {
        return artifactId;
    }

    @Override
    public void setVersion( String version )
    {
        this.version = version;
    }

    @Override
    public String getVersion()
    {
        return version;
    }

    /**
     * @param packaging
     */
    public void setPackaging( String packaging )
    {
        this.packaging = packaging;
    }

    /**
     * @return the packaging
     */
    public String getPackaging()
    {
        return packaging;
    }

    @Override
    public VersionRange getVersionRange()
    {
        return versionRange;
    }

    @Override
    public void setVersionRange( VersionRange versionRange )
    {
        this.versionRange = versionRange;
    }

    @Override
    public ArtifactHandler getArtifactHandler()
    {
        return handler;
    }

    @Override
    public void setArtifactHandler( ArtifactHandler handler )
    {
        this.handler = handler;
    }
}
