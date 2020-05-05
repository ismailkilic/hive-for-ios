//
//  LoginSignupV2.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-05-02.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import Combine
import SwiftUI

struct LoginSignupV2: View {
	@Environment(\.container) private var container: AppContainer

	@State private var account: Loadable<AccountV2> = .notLoaded
	@State private var form: Form = .login
	@State private var activeField: FieldItem?

	@State private var email: String = ""
	@State private var password: String = ""
	@State private var confirmPassword: String = ""
	@State private var displayName: String = ""

	var body: some View {
		content
			.padding(.all, length: .m)
			.avoidingKeyboard()
	}

	private var content: AnyView {
		switch account {
		case .notLoaded, .failed: return AnyView(formView)
		case .loading, .loaded: return AnyView(loadingView)
		}
	}

	private func text(for id: FieldItem) -> Binding<String> {
		switch id {
		case .email: return $email
		case .password: return $password
		case .confirmPassword: return $confirmPassword
		case .displayName: return $displayName
		}
	}

	// MARK: - Content

	private func field(for id: FieldItem) -> some View {
		LoginField(
			id.title,
			text: text(for: id),
			keyboardType: id.keyboardType,
			returnKeyType: id.returnKeyType(forForm: form),
			isActive: activeField == id,
			isSecure: id.isSecure,
			onReturn: { self.handleReturn(from: id) }
		)
		.frame(minWidth: 0, maxWidth: .infinity, minHeight: 48, maxHeight: 48)
		.onTapGesture {
			self.activeField = id
		}
	}

	private var submitButton: some View {
		Button(action: {
			self.submitForm()
		}, label: {
			Text(submitButtonText)
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
				self.toggleForm()
			}, label: {
				Text(toggleButtonText)
					.caption()
					.foregroundColor(Color(.primary))
					.padding(.vertical, length: .s)
			})
		}
	}

	private func notice(message: String) -> some View {
		Text(message)
			.body()
			.foregroundColor(Color(.highlight))
			.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
	}

	private var formView: some View {
		ScrollView {
			VStack(spacing: .m) {
				if shouldShowNotice {
					notice(message: noticeMessage)
				}

				field(for: .email)
				if form == .signup {
					field(for: .displayName)
				}
				field(for: .password)
				if form == .signup {
					field(for: .confirmPassword)
				}

				submitButton
				toggleButton
			}
		}
	}

	private var loadingView: some View {
		GeometryReader { geometry in
			HStack {
				Spacer()
				ActivityIndicator(isAnimating: true, style: .large)
				Spacer()
			}
			.padding(.top, length: .m)
			.frame(width: geometry.size.width)
		}
	}
}

// MARK: - Actions

extension LoginSignupV2 {
	var loginData: LoginData {
		LoginData(email: email, password: password)
	}

	var signupData: SignupData {
		SignupData(email: email, displayName: displayName, password: password, verifyPassword: confirmPassword)
	}

	private func nextField(after id: FieldItem) -> FieldItem? {
		switch id {
		case .email: return form == .login ? .password : .displayName
		case .displayName: return .password
		case .password: return form == .login ? nil : .confirmPassword
		case .confirmPassword: return nil
		}
	}

	private func handleReturn(from id: FieldItem) {
		if let field = nextField(after: id) {
			activeField = field
		} else {
			activeField = nil
			submitForm()
		}
	}

	private func toggleForm() {
		form = form == .login ? .signup : .login
	}

	private func submitForm() {
		switch form {
		case .login: login()
		case .signup: signup()
		}
	}

	private func login() {
		container.interactors.accountInteractor
			.login(loginData, account: $account)
	}

	private func signup() {
		container.interactors.accountInteractor
			.signup(signupData, account: $account)
	}
}

// MARK: - Form

extension LoginSignupV2 {
	enum Form {
		case login
		case signup
	}
}

// MARK: - FieldItem

extension LoginSignupV2 {
	enum FieldItem {
		case email
		case password
		case confirmPassword
		case displayName

		var isSecure: Bool {
			switch self {
			case .email, .displayName: return false
			case .password, .confirmPassword: return true
			}
		}

		var keyboardType: UIKeyboardType {
			switch self {
			case .email: return .emailAddress
			case .confirmPassword, .password, .displayName: return .default
			}
		}

		func returnKeyType(forForm form: Form) -> UIReturnKeyType {
			switch self {
			case .email, .displayName: return .next
			case .confirmPassword: return .done
			case .password: return form == .login ? .done : .next
			}
		}
	}
}

// MARK: - Strings

extension LoginSignupV2 {
	var submitButtonText: String {
		switch form {
		case .login: return "Login"
		case .signup: return "Signup"
		}
	}

	var toggleButtonText: String {
		switch form {
		case .login: return "create a new account"
		case .signup: return "login to an existing account"
		}
	}

	var shouldShowNotice: Bool {
		switch account {
		case .failed: return true
		case .loaded, .loading, .notLoaded: return false
		}
	}

	var noticeMessage: String {
		switch account {
		case .failed(let error):
			if let accountError = error as? AccountRepositoryError {
				switch accountError {
				case .loggedOut: return "You've been logged out. Please login again."
				case .apiError(let apiError): return apiError.errorDescription ?? error.localizedDescription
				case .notFound, .keychainError: return ""
				}
			}
			return error.localizedDescription
		case .loaded, .loading, .notLoaded: return ""
		}
	}
}

extension LoginSignupV2.FieldItem {
	var title: String {
		switch self {
		case .email: return "Email"
		case .password: return "Password"
		case .confirmPassword: return "Confirm password"
		case .displayName: return "Display name"
		}
	}
}