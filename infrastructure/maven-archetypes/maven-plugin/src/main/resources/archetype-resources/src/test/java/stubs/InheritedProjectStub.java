package ${package}.stubs;

public class InheritedProjectStub
    extends MyPluginProjectStub
{
    @Override
    protected String getPOM()
    {
        return "pom1.xml";
    }
}
