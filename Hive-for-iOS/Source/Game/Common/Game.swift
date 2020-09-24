//
//  Game.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-01-22.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SwiftUI
import Combine
import HiveEngine
import Loaf

struct Game: View {
	@Environment(\.container) private var container

	private let viewModel: GameViewModel

	private var playerViewModel: PlayerGameViewModel? {
		viewModel as? PlayerGameViewModel
	}

	private var spectatorViewModel: SpectatorGameViewModel? {
		viewModel as? SpectatorGameViewModel
	}

	init(setup: Setup) {
		switch setup.mode {
		case .play: viewModel = PlayerGameViewModel(setup: setup)
		case .spectate: viewModel = SpectatorGameViewModel(setup: setup)
		}
	}

//	private func handleTransition(to newState: PlayerGameViewModel.State) {
//		switch newState {
//		case .shutDown, .forfeit:
//			container.appState[\.gameSetup] = nil
//		case .begin, .gameStart, .opponentTurn, .playerTurn, .sendingMovement, .gameEnd:
//			break
//		}
//	}

	var body: some View {
		ZStack {
			gameView
				.edgesIgnoringSafeArea(.all)
			GameHUD()
				.environmentObject(viewModel)
		}
		.onAppear { self.playerViewModel?.userId = self.container.account?.userId }
		.onReceive(viewModel.gameEndPublisher) { self.container.appState[\.gameSetup] = nil }
		.navigationBarTitle("")
		.navigationBarHidden(true)
		.navigationBarBackButtonHidden(true)
		.onAppear {
			UIApplication.shared.isIdleTimerDisabled = true
			self.playerViewModel?.userId = self.container.account?.userId
			self.viewModel.clientInteractor = self.container.interactors.clientInteractor
			self.viewModel.postViewAction(.onAppear)
		}
		.onDisappear {
			UIApplication.shared.isIdleTimerDisabled = true
			self.viewModel.postViewAction(.onDisappear)
		}
	}

	private var gameView: AnyView {
		#if targetEnvironment(simulator)
		return AnyView(GameView2DContainer(viewModel: viewModel))
		#else
		switch container.appState.value.preferences.gameMode {
		case .ar: return AnyView(GameViewARContainer(viewModel: viewModel))
		case .sprite: return AnyView(GameView2DContainer(viewModel: viewModel))
		}
		#endif
	}
}

// MARK: Game Setup

extension Game {
	struct Setup: Equatable {
		let state: GameState
		let mode: Mode
	}
}

extension Game.Setup {
	enum Mode: Equatable {
		case play(player: Player, configuration: ClientInteractorConfiguration)
		case spectate
	}
}
