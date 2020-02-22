package ${package}.stubs;

import org.apache.maven.artifact.handler.DefaultArtifactHandler;

public class DefaultArtifactHandlerStub
    extends DefaultArtifactHandler
{
    private String language;

    @Override
    public String getLanguage()
    {
        if ( language == null )
        {
            language = "java";
        }

        return language;
    }

    /**
     * @param language the language. Defaults to "java".
     */
    public void setLanguage( String language )
    {
        this.language = language;
    }
}
