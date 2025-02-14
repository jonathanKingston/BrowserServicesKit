//
//  SecureVaultFactory.swift
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

/// Can make a SecureVault instance with given specification.  May return previously created instance if specification is unchanged.
public class SecureVaultFactory {

    public static let `default` = SecureVaultFactory()

    private var lock = NSLock()
    private var vault: DefaultSecureVault?

    /// You should really use the `default` accessor.
    public init() {
    }

    /// Returns an initialised SecureVault instance that respects the user password for the specified amount of time.
    ///
    /// After this time has expired, the SecureVault will return errors for accessing L2 and above data. The default
    /// expiry is 72 hours.  This can be overriden so that the user can choose to extend the length between
    /// password prompts.
    ///
    /// The first time this is ever called the following is performed:
    /// * Generates a secret key for L1 encryption and stores in Keychain
    /// * Generates a secret key for L2 encryption
    /// * Generates a user password to encrypt the L2 key with
    /// * Stores encyprted L2 key in Keychain
    public func makeVault(authExpiration: TimeInterval = 60 * 60 * 24 * 72) throws -> SecureVault {

        if let vault = self.vault, authExpiration == vault.authExpiry {
            return vault
        } else {
            lock.lock()
            defer {
                lock.unlock()
            }

            let cryptoProvider = makeCryptoProvider()
            let keystoreProvider = makeKeyStoreProvider()
            let databaseProvider: SecureVaultDatabaseProvider

            do {
                if let existingL1Key = try keystoreProvider.l1Key() {
                    databaseProvider = try DefaultDatabaseProvider(key: existingL1Key)
                } else {
                    let l1Key = try cryptoProvider.generateSecretKey()
                    let l2Key = try cryptoProvider.generateSecretKey()
                    let password = try cryptoProvider.generatePassword()
                    let passwordKey = try cryptoProvider.deriveKeyFromPassword(password)
                    let encryptedL2Key = try cryptoProvider.encrypt(l2Key, withKey: passwordKey)

                    try keystoreProvider.storeEncryptedL2Key(encryptedL2Key)
                    try keystoreProvider.storeGeneratedPassword(password)
                    try keystoreProvider.storeL1Key(l1Key)

                    databaseProvider = try DefaultDatabaseProvider(key: l1Key)
                }

                let providers = SecureVaultProviders(crypto: cryptoProvider, database: databaseProvider, keystore: keystoreProvider)

                let vault = DefaultSecureVault(authExpiry: authExpiration, providers: providers)
                self.vault = vault
                return vault

            } catch {
                throw SecureVaultError.initFailed(cause: error)
            }
        }

    }

    internal func makeCryptoProvider() -> SecureVaultCryptoProvider {
        return DefaultCryptoProvider()
    }

    internal func makeDatabaseProvider(key: Data) throws -> SecureVaultDatabaseProvider {
        return try DefaultDatabaseProvider(key: key)
    }

    internal func makeKeyStoreProvider() -> SecureVaultKeyStoreProvider {
        return DefaultKeyStoreProvider()
    }

}
