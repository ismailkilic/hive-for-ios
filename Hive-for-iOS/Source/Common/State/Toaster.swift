//
//  Toaster.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-04-25.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SwiftUI
import Combine
import Loaf

struct Toaster: EnvironmentKey {
	let loaf: Store<LoafState?>

	static var defaultValue: Self { self.default }

	private static let `default` = Self(loaf: .init(nil))
}

extension EnvironmentValues {
	var toaster: Toaster {
		get { self[Toaster.self] }
		set { self[Toaster.self] = newValue }
	}
}

struct LoafModifier: ViewModifier {
	@Environment(\.toaster) private var toaster
	@State private var loaf: Loaf?
	@State private var presentedLoafs: Set<LoafState> = []

	func body(content: Content) -> some View {
		content
			.loaf($loaf)
			.onReceive(loafUpdate) {
				guard !presentedLoafs.contains($0) else { return }
				presentedLoafs.insert($0)
				loaf = $0.build()
			}
	}

	private var loafUpdate: AnyPublisher<LoafState, Never> {
		toaster.loaf
			.filter { $0 != nil }
			.map { $0! }
			.eraseToAnyPublisher()
	}
}

extension View {
	func plugInToaster() -> some View {
		self.modifier(LoafModifier())
	}
}
