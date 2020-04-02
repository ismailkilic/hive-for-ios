//
//  Account.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-04-01.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Foundation
import Combine
import KeychainAccess

class Account: ObservableObject {
	private enum Key: String {
		case userId
		case accessToken
	}

	@Published var userId: User.ID?
	@Published var accessToken: String?

	var accountLoaded = CurrentValueSubject<Bool, Never>(false)

	private let keychain = Keychain(service: "ca.josephroque.hive-for-ios")

	init() {
		do {
			guard let id = try keychain.get(Key.userId.rawValue) else { return }
			guard let token = try keychain.get(Key.accessToken.rawValue) else { return }

			userId = UUID(uuidString: id)
			accessToken = token
		} catch {
			print("Error retrieving login: \(error)")
		}
	}

	func clear() throws {
		try store(userId: nil)
		try store(accessToken: nil)
	}

	func store(accessToken: AccessToken) throws {
		try store(userId: accessToken.userId)
		try store(accessToken: accessToken.token)
	}

	private func store(userId: User.ID?) throws {
		if let userId = userId {
			try keychain.set(userId.uuidString, key: Key.userId.rawValue)
		} else {
			try keychain.remove(Key.userId.rawValue)
		}
	}

	private func store(accessToken: String?) throws {
		if let accessToken = accessToken {
			try keychain.set(accessToken, key: Key.accessToken.rawValue)
		} else {
			try keychain.remove(Key.accessToken.rawValue)
		}
	}
}