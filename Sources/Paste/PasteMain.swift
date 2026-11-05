import PasteKit

@main
struct PasteMain {
    static func main() {
        MainActor.assumeIsolated {
            PasteApplication.run()
        }
    }
}
