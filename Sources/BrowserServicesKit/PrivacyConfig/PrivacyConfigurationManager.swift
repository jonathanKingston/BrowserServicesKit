//
//  PrivacyConfigurationManager.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public protocol PrivacyConfigurationDataProvider {

    func downloadedPrivacyConfig() -> Data?
    func embeddedPrivacyConfig() -> Data
}

public class PrivacyConfigurationManager {
    public struct Constants {
        public static let embeddedConfigETag = "\"a4bae5e53ca1ac5e1ad7ebd5a2bc3f5a\""
        public static let embeddedConfigurationSHA = "S2/XfJs7hKiPAX1h1j8w06g/3N5vOVLi4BuDWcEQCus="
    }
    
    public enum ReloadResult {
        case embedded
        case embeddedFallback
        case downloaded
    }

    enum ParsingError: Error {
        case dataMismatch
    }
    
    public typealias ConfigurationData = (data: PrivacyConfigurationData, etag: String)
    
    private let lock = NSLock()
    private let dataProvider: PrivacyConfigurationDataProvider
    
    private var _fetchedConfigData: ConfigurationData?
    private(set) public var fetchedConfigData: ConfigurationData? {
        get {
            lock.lock()
            let data = _fetchedConfigData
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _fetchedConfigData = newValue
            lock.unlock()
        }
    }
    
    private var _embeddedConfigData: ConfigurationData!
    private(set) public var embeddedConfigData: ConfigurationData {
        get {
            lock.lock()

            let data: ConfigurationData
            // List is loaded lazily when needed
            if let embedded = _embeddedConfigData {
                data = embedded
            } else {
                let jsonData = dataProvider.embeddedPrivacyConfig()
                let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                let configData = PrivacyConfigurationData(json: json!)
                _embeddedConfigData = (configData, Constants.embeddedConfigETag)
                data = _embeddedConfigData
            }
            lock.unlock()
            return data
        }
        set {
            lock.lock()
            _embeddedConfigData = newValue
            lock.unlock()
        }
    }

    public init(dataProvider: PrivacyConfigurationDataProvider) {
        self.dataProvider = dataProvider

//        reload(etag: UserDefaultsETagStorage().etag(for: .privacyConfiguration)) FIXME
    }
    
//    public static let shared = PrivacyConfigurationManager()
    
    public var privacyConfig: PrivacyConfiguration {
        fatalError("Subclass expected")
    }
    
    @discardableResult
    public func reload(etag: String?) -> ReloadResult {
        
        let result: ReloadResult
        
        if let etag = etag, let data = dataProvider.downloadedPrivacyConfig() {
            result = .downloaded
            
            do {
                // This might fail if the downloaded data is corrupt or format has changed unexpectedly
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let configData = PrivacyConfigurationData(json: json)
                    fetchedConfigData = (configData, etag)
                } else {
                    throw ParsingError.dataMismatch
                }
            } catch {
//                Pixel.fire(pixel: .privacyConfigurationParseFailed, error: error)
                fetchedConfigData = nil
                return .embeddedFallback
            }
        } else {
            fetchedConfigData = nil
            result = .embedded
        }
        
        return result
    }
}
