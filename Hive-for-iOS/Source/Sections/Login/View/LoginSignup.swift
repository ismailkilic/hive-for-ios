//
//  LoginSignup.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-03-30.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SwiftUI

struct LoginSignup: View {
	@ObservedObject private var viewModel = LoginSignupViewModel()

	@State private var email: String = ""
	@State private var password: String = ""
	@State private var confirmPassword: String = ""
	@State private var displayName: String = ""

	private var loginSignupData: LoginSignupData {
		LoginSignupData(email: email, displayName: displayName, password: password, verifyPassword: confirmPassword)
	}

	private func text(for id: LoginFieldID) -> Binding<String> {
		switch id {
		case .email: return $email
		case .password: return $password
		case .verifyPassword: return $confirmPassword
		case .displayName: return $displayName
		}
	}

	private func field(id: LoginFieldID) -> some View {
		return LoginField(
			id.title,
			text: self.text(for: id),
			isActive: viewModel.isActive(field: id),
			isSecure: id.isSecure
		)
			.frame(minWidth: 0, maxWidth: .infinity, minHeight: 48, maxHeight: 48)
			.onTapGesture {
				self.viewModel.postViewAction(.focusedField(id))
			}
	}

	private var loginButton: some View {
		Button(action: {
			self.viewModel.postViewAction(.loginSignup(self.loginSignupData))
		}, label: {
			Text(self.viewModel.loggingIn ? "Login" : "Signup")
				.body()
				.foregroundColor(Color(.background))
				.padding(.vertical, length: .m)
				.frame(minWidth: 0, maxWidth: .infinity)
				.background(
					RoundedRectangle(cornerRadius: .s)
						.fill(Color(.actionSheetBackground))
				)
		})
	}

	private var toggleButton: some View {
		HStack(spacing: 0) {
			Text("or ")
				.caption()
				.foregroundColor(Color(.text))
			Button(action: {
				self.viewModel.postViewAction(.toggleMethod)
			}, label: {
				Text(self.viewModel.loggingIn
					? "create a new account"
					: "login to an existing account")
					.caption()
					.foregroundColor(Color(.primary))
					.padding(.vertical, length: .s)
			})
		}
	}

	var body: some View {
		ScrollView {
			VStack(spacing: Metrics.Spacing.m.rawValue) {
				self.field(id: .email)
				if !viewModel.loggingIn {
					self.field(id: .displayName)
				}
				self.field(id: .password)
				if !viewModel.loggingIn {
					self.field(id: .verifyPassword)
				}

				VStack(spacing: Metrics.Spacing.m.rawValue) {
					loginButton
					toggleButton
				}
			}
				.padding(.horizontal, length: .m)
				.padding(.vertical, length: .xl)
		}
			.avoidingKeyboard()
	}
}

#if DEBUG
struct LoginSignup_Previews: PreviewProvider {
	static var previews: some View {
		LoginSignup()
	}
}
#endif
