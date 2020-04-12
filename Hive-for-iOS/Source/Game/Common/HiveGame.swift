//
//  HiveGame.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-01-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SwiftUI
import HiveEngine
import Loaf

struct HiveGame: View {
	@Environment(\.presentationMode) var presentationMode
	@ObservedObject var viewModel: HiveGameViewModel
	private let stateBuilder: () -> GameState?

	init(client: HiveGameClient, stateBuilder: @escaping () -> GameState?) {
		self.stateBuilder = stateBuilder
		viewModel = HiveGameViewModel(client: client)

		#warning("TODO: set the player based on whether they are host or opponent")
		viewModel.playingAs = .white
	}

	private func handleTransition(to newState: HiveGameViewModel.State) {
		switch newState {
		case .forfeit:
			presentationMode.wrappedValue.dismiss()
		case .begin, .gameEnd, .gameStart, .opponentTurn, .playerTurn, .sendingMovement:
			break
		}
	}

	var body: some View {
		ZStack {
			#if targetEnvironment(simulator)
			Hive2DGame(viewModel: viewModel)
				.edgesIgnoringSafeArea(.all)
			#else
			Hive2DGame(viewModel: viewModel)
				.edgesIgnoringSafeArea(.all)
//			HiveARGame(viewModel: viewModel)
			#endif
			GameHUD().environmentObject(viewModel)
		}
		.onReceive(viewModel.flowStateSubject) { receivedValue in self.handleTransition(to: receivedValue) }
		.navigationBarTitle("")
		.navigationBarHidden(true)
		.navigationBarBackButtonHidden(true)
		.onAppear {
			guard let state = self.stateBuilder() else {
				self.viewModel.postViewAction(.failedToStartGame)
				self.presentationMode.wrappedValue.dismiss()
				return
			}

			self.viewModel.postViewAction(.onAppear(state))
		}
	}
}
