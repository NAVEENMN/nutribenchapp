//
//  Endpoints.swift
//  nutribench
//

import Foundation

enum APIEndpoints {
    /// Base URL for DB/Lambda that handles users, events, health summaries, image upload URLs, etc.
    static let backendBase = URL(
        string: "https://k6wbwg2lh5dgsb7yso2bi3dsta0nhmdy.lambda-url.us-west-2.on.aws/"
    )!

    /// Nutrition inference Lambda (used by LogFoodSheet + Page2ViewModel legacy submit).
    static let nutritionInference = URL(
        string: "https://5lcj2njvoq4urxszpj7lqoatxy0gslkf.lambda-url.us-west-2.on.aws/"
    )!
}
