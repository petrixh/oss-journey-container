public class Greeter {
    public String greet() {
        return decorate("v2");
    }

    // Adding a method is a schema change: plain HotSpot refuses to redefine
    // the class, JetBrains Runtime with -XX:+AllowEnhancedClassRedefinition allows it.
    private String decorate(String s) {
        return s + "+new-method";
    }
}
