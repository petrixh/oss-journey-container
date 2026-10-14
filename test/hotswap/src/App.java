public class App {
    public static void main(String[] args) throws Exception {
        while (true) {
            System.out.println("greeting=" + new Greeter().greet());
            Thread.sleep(500);
        }
    }
}
