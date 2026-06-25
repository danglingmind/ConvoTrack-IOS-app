import GoogleMaps

enum GoogleMapsConfig {
    static let apiKey = "AIzaSyCIPU5oxxXVLrdQce5V-cvJMZ8KDbbgrlQ"

    static func initialize() {
        GMSServices.provideAPIKey(apiKey)
    }
}
