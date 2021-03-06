//
//  GameViewModel.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-01-24.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SwiftUI
import Combine
import HiveEngine
import Loaf

enum GameViewAction: BaseViewAction {
	case onAppear
	case viewContentDidLoad(GameViewContent)
	case viewContentReady
	case viewInteractionsReady

	case presentInformation(GameInformation)
	case closeInformation(withFeedback: Bool)

	case openHand(Player)
	case selectedFromHand(Player, Piece.Class)
	case enquiredFromHand(Piece.Class)
	case tappedPiece(Piece)
	case tappedGamePiece(Piece)

	case toggleEmojiPicker
	case pickedEmoji(Emoji)

	case gamePieceSnapped(Piece, Position)
	case gamePieceMoved(Piece, Position)
	case movementConfirmed(Movement)
	case cancelMovement

	case hasMovedInBounds
	case hasMovedOutOfBounds
	case returnToGameBounds

	case openSettings
	case forfeit
	case forfeitConfirmed
	case returnToLobby
	case arViewError(Error)

	case toggleDebug
	case onDisappear
}

class GameViewModel: ViewModel<GameViewAction>, ObservableObject {
	var clientInteractor: ClientInteractor!

	@Published var state: State = .begin
	@Published var gameState: GameState
	@Published var debugMode = false

	@Published var isOutOfBounds = false

	struct SelectedPiece {
		let piece: Piece
		let position: Position
	}

	@Published var selectedPiece: (deselected: SelectedPiece?, selected: SelectedPiece?) = (nil, nil)

	@Published var showingEmojiPicker: Bool = false
	@Published var presentedGameAction: GameAction?
	@Published var presentedGameInformation: GameInformation? {
		didSet {
			if presentedGameInformation != nil && showingEmojiPicker {
				showingEmojiPicker = false
			}

			if case .playerMustPass = oldValue {
				postViewAction(.movementConfirmed(.pass))
			}
		}
	}

	private(set) var loafState = PassthroughSubject<LoafState, Never>()
	private(set) var animateToPosition = PassthroughSubject<Position, Never>()
	private(set) var animatedEmoji = PassthroughSubject<Emoji, Never>()

	var userId: User.ID!
	var playingAs: Player
	var clientMode: ClientInteractorConfiguration
	private(set) var gameContent: GameViewContent!

	private var connectionOpened = false
	private var reconnectAttempts = 0
	private var reconnecting = false

	private let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
	private let actionFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
	private let promptFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

	var inGame: Bool {
		state.inGame
	}

	#if AR_AVAILABLE
	var gameAnchor: Experience.HiveGame? {
		if case let .arExperience(anchor) = gameContent {
			return anchor
		} else {
			return nil
		}
	}
	#endif

	var presentingGameInformation: Binding<Bool> {
		Binding(
			get: { [weak self] in self?.presentedGameInformation != nil },
			set: { [weak self] newValue in
				guard !newValue else { return }
				self?.presentedGameInformation = nil
			}
		)
	}

	var presentingGameAction: Binding<Bool> {
		Binding(
			get: { [weak self] in self?.presentedGameAction != nil },
			set: { [weak self] newValue in
				guard !newValue else { return }
				self?.presentedGameAction?.onClose?()
				self?.presentedGameAction = nil
			}
		)
	}

	var shouldHideHUDControls: Bool {
		presentingGameInformation.wrappedValue || presentingGameAction.wrappedValue
	}

	private var viewContentReady = false
	private var viewInteractionsReady = false

	init(setup: Game.Setup) {
		self.gameState = setup.state
		switch setup.mode {
		case .spectate:
			self.playingAs = .white
			self.clientMode = .online
		case .play(let player, let configuration):
			self.playingAs = player
			self.clientMode = configuration
		}
	}

	override func postViewAction(_ viewAction: GameViewAction) {
		switch viewAction {
		case .onAppear:
			openConnection()
		case .viewContentDidLoad(let content):
			setupView(content: content)
		case .viewContentReady:
			viewContentReady = true
			setupNewGame()
		case .viewInteractionsReady:
			viewInteractionsReady = true
			setupNewGame()

		case .presentInformation(let information):
			presentedGameInformation = information
		case .closeInformation(let withFeedback):
			if withFeedback {
				actionFeedbackGenerator.impactOccurred()
			}
			presentingGameInformation.wrappedValue = false

		case .openHand(let player):
			promptFeedbackGenerator.impactOccurred()
			postViewAction(.presentInformation(.playerHand(.init(player: player, playingAs: playingAs, state: gameState))))
		case .selectedFromHand(let player, let pieceClass):
			selectFromHand(player, pieceClass)
		case .enquiredFromHand(let pieceClass):
			enquireFromHand(pieceClass)
		case .tappedPiece(let piece):
			tappedPiece(piece)
		case .tappedGamePiece(let piece):
			tappedPiece(piece, showStack: true)
		case .gamePieceSnapped(let piece, let position):
			updatePosition(of: piece, to: position, shouldMove: false)
		case .gamePieceMoved(let piece, let position):
			debugLog("Moving \(piece) to \(position)")
			updatePosition(of: piece, to: position, shouldMove: true)
		case .movementConfirmed(let movement):
			debugLog("Sending move \(movement)")
			apply(movement: movement)
		case .cancelMovement:
			clearSelectedPiece()
			updateGameState(to: gameState)

		case .toggleEmojiPicker:
			promptFeedbackGenerator.impactOccurred()
			showingEmojiPicker.toggle()
		case .pickedEmoji(let emoji):
			pickedEmoji(emoji)

		case .openSettings:
			openSettings()

		case .forfeit:
			promptForfeit()
		case .forfeitConfirmed:
			forfeitGame()
		case .returnToLobby:
			shutDownGame()
		case .arViewError(let error):
			loafState.send(LoafState(error.localizedDescription, state: .error))

		case .hasMovedInBounds:
			isOutOfBounds = false
		case .hasMovedOutOfBounds:
			isOutOfBounds = true
		case .returnToGameBounds:
			isOutOfBounds = false
			animateToPosition.send(.origin)

		case .toggleDebug:
			debugMode.toggle()
		case .onDisappear:
			cleanUp()
		}
	}

	private func openConnection() {
		guard !connectionOpened else { return }
		connectionOpened = true
		clientInteractor.reconnect(clientMode)
			.sink(
				receiveCompletion: { [weak self] in
					if case let .failure(error) = $0 {
						self?.handleGameClientError(error)
					}
				}, receiveValue: { [weak self] in
					self?.handleGameClientEvent($0)
				}
			)
			.store(in: self)
	}

	private func cleanUp() {
		clientInteractor.close(clientMode)
	}

	private func setupNewGame() {
		guard !inGame && viewContentReady && viewInteractionsReady else { return }
		if gameState.currentPlayer == playingAs {
			transition(to: .playerTurn)
		} else {
			transition(to: .opponentTurn)
		}

		// Let the computer know it's time to play, if offline
		if case .local = clientMode {
			clientInteractor.send(.local, .readyToPlay, completionHandler: nil)
		}
	}

	private func setupView(content: GameViewContent) {
		if gameContent == nil {
			self.gameContent = content
			transition(to: .gameStart)
		}
	}

	private func pickedEmoji(_ emoji: Emoji) {
		guard Emoji.canSend(emoji: emoji) else { return }

		promptFeedbackGenerator.impactOccurred()
		animatedEmoji.send(emoji)
		clientInteractor.send(clientMode, .message("EMOJI {\(emoji.rawValue)}")) { _ in }
		Emoji.didSend(emoji: emoji)
	}

	private func clearSelectedPiece() {
		selectedPiece = (selectedPiece.selected, nil)
	}

	private func selectFromHand(_ player: Player, _ pieceClass: Piece.Class) {
		guard inGame else { return }
		if player == playingAs {
			placeFromHand(pieceClass)
		} else {
			enquireFromHand(pieceClass)
		}
	}

	private func placeFromHand(_ pieceClass: Piece.Class) {
		guard inGame else { return }
		actionFeedbackGenerator.impactOccurred()
		if let piece = gameState.firstUnplayed(of: pieceClass, inHand: playingAs) {
			let position = selectedPieceDefaultPosition
			selectedPiece = (
				selectedPiece.selected,
				SelectedPiece(
					piece: piece,
					position: position
				)
			)
			animateToPosition.send(position)
		}
	}

	private func enquireFromHand(_ pieceClass: Piece.Class) {
		guard inGame else { return }
		actionFeedbackGenerator.impactOccurred()
		presentedGameInformation = .pieceClass(pieceClass)
	}

	private func tappedPiece(_ piece: Piece, showStack: Bool = false) {
		promptFeedbackGenerator.impactOccurred()
		if showStack {
			let position = self.position(of: piece)
			guard let stack = gameState.stacks[position] else {
				presentedGameInformation = .piece(piece)
				return
			}

			let (_, stackCount) = self.positionInStack(of: piece)
			if stackCount > 1 {
				let stackAddition = stackCount > stack.count ? [selectedPiece.selected?.piece].compactMap { $0 } : []
				presentedGameInformation = .stack(stack + stackAddition)
				return
			}
		}
		presentedGameInformation = .piece(piece)
	}

	private func openSettings() {
		promptFeedbackGenerator.impactOccurred()
		presentedGameInformation = .settings
	}

	private func forfeitGame() {
		guard inGame else { return }

		clientInteractor.send(clientMode, .forfeit, completionHandler: nil)
		transition(to: .forfeit)
	}

	private func endGame() {
		guard inGame else { return }
		transition(to: .gameEnd)
	}

	private func shutDownGame() {
		transition(to: .shutDown)
	}

	private func promptForfeit() {
		guard inGame else { return }

		let popoverSheet = PopoverSheetConfig(
			title: "Forfeit match?",
			message: "This will count as a loss in your statistics. Are you sure?",
			buttons: [
				PopoverSheetConfig.ButtonConfig(
					title: "Forfeit",
					type: .destructive
				) { [weak self] in
					self?.postViewAction(.forfeitConfirmed)
					self?.presentedGameAction = nil
				},
				PopoverSheetConfig.ButtonConfig(
					title: "Cancel",
					type: .cancel
				) { [weak self] in
					self?.presentedGameAction = nil
				},
			]
		)

		promptFeedbackGenerator.impactOccurred()
		presentedGameAction = GameAction(config: popoverSheet, onClose: nil)
	}

	private func updatePosition(of piece: Piece, to position: Position?, shouldMove: Bool) {
		guard inGame else { return }
		guard let targetPosition = position else {
			selectedPiece = (selectedPiece.selected, nil)
			return
		}

		guard shouldMove else {
			selectedPiece = (selectedPiece.selected, SelectedPiece(piece: piece, position: targetPosition))
			return
		}

		guard let movement = gameState.availableMoves.first(where: {
			$0.movedUnit == piece && $0.targetPosition == targetPosition
		}), let relativeMovement = movement.relative(in: gameState) else {
			debugLog("Did not find \"\(piece) to \(targetPosition)\" in \(gameState.availableMoves)")
			notificationFeedbackGenerator.notificationOccurred(.warning)
			return
		}

		selectedPiece = (selectedPiece.selected, SelectedPiece(piece: piece, position: targetPosition))

		let inHand = gameState.position(of: piece) == nil

		let popoverSheet = PopoverSheetConfig(
			title: "\(inHand ? "Place" : "Move") \(piece.class.description)?",
			message: description(of: relativeMovement, inHand: inHand),
			buttons: [
				PopoverSheetConfig.ButtonConfig(
					title: "Move",
					type: .default
				) { [weak self] in
					self?.postViewAction(.movementConfirmed(movement))
					self?.presentedGameAction = nil
				},
				PopoverSheetConfig.ButtonConfig(
					title: "Cancel",
					type: .cancel
				) { [weak self] in
					self?.postViewAction(.cancelMovement)
					self?.presentedGameAction = nil
				},
			]
		)

		promptFeedbackGenerator.impactOccurred()
		presentedGameAction = GameAction(config: popoverSheet) { [weak self] in
			self?.postViewAction(.cancelMovement)
		}
	}

	private func apply(movement: Movement) {
		guard let relativeMovement = movement.relative(in: gameState) else {
			notificationFeedbackGenerator.notificationOccurred(.error)
			return
		}

		notificationFeedbackGenerator.notificationOccurred(.success)
		transition(to: .sendingMovement(movement))
		clientInteractor.send(clientMode, .movement(relativeMovement), completionHandler: nil)
	}

	private func updateGameState(to newState: GameState) {
		guard inGame else { return }
		let previousState = gameState
		self.gameState = newState

		let opponent = playingAs.next
		guard let previousUpdate = newState.updates.last,
			previousUpdate != previousState.updates.last else {
			return
		}

		let wasOpponentMove = previousUpdate.player == opponent

		if newState.hasGameEnded {
			endGame()
		} else {
			transition(to: wasOpponentMove ? .playerTurn : .opponentTurn)
		}

		guard wasOpponentMove else { return }

		let message: String
		let image: UIImage
		switch previousUpdate.movement {
		case .pass:
			message = "\(opponent) passed"
			image = ImageAsset.Movement.pass
		case .move(let unit, _), .yoink(_, let unit, _):
			if unit.owner == opponent {
				message = "\(opponent) moved their \(unit.class)"
				image = ImageAsset.Movement.move
			} else {
				message = "\(opponent) yoinked your \(unit.class)"
				image = ImageAsset.Movement.yoink
			}
		case .place(let unit, _):
			message = "\(opponent) placed their \(unit.class)"
			image = ImageAsset.Movement.place
		}

		loafState.send(LoafState(
			message,
			state: .custom(Loaf.Style(
				backgroundColor: UIColor(.backgroundRegular),
				textColor: UIColor(.textRegular),
				icon: image)
			)) { [weak self] dismissalReason in
				guard let self = self,
					dismissalReason == .tapped,
					let position = previousUpdate.movement.targetPosition else { return }
				self.animateToPosition.send(position)
			}
		)
	}

	private func handleMessage(_ message: String, from id: UUID) {
		guard id != self.userId else { return }
		if let emoji = Emoji.from(message: message) {
			guard Emoji.canReceive(emoji: emoji) else { return }
			animatedEmoji.send(emoji)
			Emoji.didReceive(emoji: emoji)
		}
	}
}

// MARK: - GameClient

extension GameViewModel {
	private func handleGameClientError(_ error: GameClientError) {
		switch error {
		case .usingOfflineAccount, .notPrepared, .missingURL:
			break
		case .failedToConnect:
			attemptToReconnect(error: error)
		case .webSocketError(let error):
			attemptToReconnect(error: error)
		}
	}

	private func attemptToReconnect(error: Error?) {
		debugLog("Client did not connect: \(String(describing: error))")

		guard reconnectAttempts < OnlineGameClient.maxReconnectAttempts else {
			loafState.send(LoafState("Failed to reconnect", state: .error))
			transition(to: .gameEnd)
			return
		}

		reconnecting = true
		reconnectAttempts += 1
		presentedGameInformation = .reconnecting(reconnectAttempts)

		openConnection()
	}

	private func onClientConnected() {
		reconnecting = false
		reconnectAttempts = 0
		debugLog("Connected to client.")

		switch presentedGameInformation {
		case .reconnecting:
			postViewAction(.closeInformation(withFeedback: true))
		case .piece, .pieceClass, .playerHand, .stack, .rule, .gameEnd, .settings, .playerMustPass, .none:
			break
		}
	}

	private func handleGameClientEvent(_ event: GameClientEvent) {
		switch event {
		case .connected, .alreadyConnected:
			onClientConnected()
			self.connectionOpened = false
		case .message(let message):
			handleGameClientMessage(message)
		}
	}

	private func handleGameClientMessage(_ message: GameServerMessage) {
		switch message {
		case .gameState(let state):
			updateGameState(to: state)
		case .gameOver(let winner):
			endGame()
			promptFeedbackGenerator.impactOccurred()
			presentedGameInformation = .gameEnd(.init(
				winner: winner == nil
					? nil
					: (
						winner == userId
							? playingAs
							: playingAs.next
					),
				playingAs: playingAs
			))
		case .message(let id, let message):
			handleMessage(message, from: id)
		case .error, .forfeit, .playerJoined, .playerLeft, .playerReady, .setOption:
			#warning("TODO: handle remaining messages in game")
			debugLog("Received message: \(message)")
		}
	}
}

// MARK: - Position

extension GameViewModel {
	/// Returns the position in the stack and the total number of pieces in the stack
	func positionInStack(of piece: Piece) -> (Int, Int) {
		let position = self.position(of: piece)
		if let stack = gameState.stacks[position] {
			let selectedPieceInStack: Bool
			let selectedPieceOnStack: Bool
			let selectedPieceFromStack: Bool
			if let selectedPiece = selectedPiece.selected {
				selectedPieceInStack = stack.contains(selectedPiece.piece)
				selectedPieceOnStack = !selectedPieceInStack && selectedPiece.position == position
				selectedPieceFromStack = selectedPieceInStack && selectedPiece.position != position
			} else {
				selectedPieceInStack = false
				selectedPieceOnStack = false
				selectedPieceFromStack = false
			}

			let additionalStackPieces = selectedPieceOnStack ? 1 : (selectedPieceFromStack ? -1 : 0)
			let stackCount = stack.count + additionalStackPieces

			if let indexInStack = stack.firstIndex(of: piece) {
				return (indexInStack + 1, stackCount)
			} else {
				return (stackCount, stackCount)
			}
		} else {
			return (1, 1)
		}
	}

	/// Returns the current position of the piece, accounting for the selected piece, and it's in game position
	func position(of piece: Piece) -> Position {
		if selectedPiece.selected?.piece == piece,
			let selectedPosition = selectedPiece.selected?.position {
			return selectedPosition
		} else if let gamePosition = gameState.position(of: piece) {
			return gamePosition
		} else {
			return .origin
		}
	}

	private var selectedPieceDefaultPosition: Position {
		let piecePositions = Set(gameState.stacks.keys)
		let placeablePositions = gameState.placeablePositions(for: playingAs)
		let adjacentToPiecePositions = Set(piecePositions.flatMap { $0.adjacent() })
			.subtracting(piecePositions)
		let adjacentToAdjacentPositions = Set(adjacentToPiecePositions.flatMap { $0.adjacent() })
			.subtracting(adjacentToPiecePositions)
			.subtracting(piecePositions)
			.sorted()

		guard let startingPosition = adjacentToAdjacentPositions.first else {
			// Fallback for when the algorithm fails, which it shouldn't ever do
			// Places the piece to the far left of the board, vertically centred.
			let startX = piecePositions.first?.x ?? 0
			let minX = piecePositions.reduce(startX, { minX, position in min(minX, position.x) })
			let x = minX - 2
			let z = x < 0 ? -x / 2 : Int((Double(-x) / 2.0).rounded(.down))
			return Position(x: x, y: -x - z, z: z)
		}

		let closest = adjacentToAdjacentPositions.reduce(
			(startingPosition, CGFloat.greatestFiniteMagnitude)
		) { closest, position in
			let totalDistanceToPlaceable = placeablePositions.reduce(.zero) { total, next in
				total + position.distance(to: next)
			}

			return totalDistanceToPlaceable < closest.1
				? (position, totalDistanceToPlaceable)
				: closest
		}

		return closest.0
	}
}

// MARK: - State

extension GameViewModel {
	enum State: Equatable {
		case begin
		case gameStart
		case playerTurn
		case opponentTurn
		case sendingMovement(Movement)
		case gameEnd
		case forfeit
		case shutDown

		var inGame: Bool {
			switch self {
			case .begin, .gameStart, .gameEnd, .forfeit, .shutDown: return false
			case .playerTurn, .opponentTurn, .sendingMovement: return true
			}
		}
	}

	func transition(to nextState: State) {
		guard canTransition(from: state, to: nextState) else { return }
		state = nextState

		guard nextState == .playerTurn else { return }

		if gameState.currentPlayer == playingAs && gameState.availableMoves == [.pass] {
			presentedGameInformation = .playerMustPass
		}
	}

	private func canTransition(from currentState: State, to nextState: State) -> Bool {
		switch (currentState, nextState) {

		// Forfeit and shutDown are final states
		case (.forfeit, _): return false
		case (.shutDown, _): return false

		// Forfeiting possible at any time
		case (_, .forfeit): return true

		// View can be dismissed at any time
		case (_, .shutDown): return true

		// Game can be ended at any time
		case (_, .gameEnd): return true

		// Beginning the game always transitions to the start of a game
		case (.begin, .gameStart): return true
		case (.begin, _): return false
		case (_, .begin): return false
		case (_, .gameStart): return false

		// The start of a game leads to a player's turn or an opponent's turn
		case (.gameStart, .playerTurn), (.gameStart, .opponentTurn): return true
		case (.gameStart, _): return false

		// The player must send moves
		case (.playerTurn, .sendingMovement): return true
		case (.playerTurn, _): return false

		// A played move leads to a new turn
		case (.sendingMovement, .opponentTurn): return true
		case (.opponentTurn, .playerTurn): return true
		case (.opponentTurn, _): return false

		case (.sendingMovement, _), (_, .sendingMovement): return false
		case (_, .playerTurn), (_, .opponentTurn): return false

		}
	}
}

// MARK: - Image

extension GameViewModel {
	func handImage(for player: Player) -> UIImage {
		if player == playingAs {
			return state == .playerTurn ? ImageAsset.Icon.handFilled : ImageAsset.Icon.handOutlined
		} else {
			return state == .opponentTurn ? ImageAsset.Icon.handFilled : ImageAsset.Icon.handOutlined
		}
	}
}

// MARK: - Strings

extension GameViewModel {
	var displayState: String {
		switch state {
		case .playerTurn:
			return "Your turn"
		case .sendingMovement:
			return "Sending movement..."
		case .opponentTurn:
			return "Opponent's turn"
		case .gameEnd:
			return gameState.displayWinner ?? ""
		case .begin, .forfeit, .gameStart, .shutDown:
			return ""
		}
	}

	private func description(of movement: RelativeMovement, inHand: Bool) -> String {
		if let adjacent = movement.adjacent {
			let direction = adjacent.direction.flipped
			return "\(inHand ? "Place" : "Move") "
				+ "\(movement.movedUnit.description) \(direction.description.lowercased()) of \(adjacent.unit)?"
		} else {
			return "Place \(movement.movedUnit.description)?"
		}

	}
}

private extension Direction {
	var flipped: Direction {
		switch self {
		case .north: return .south
		case .northWest: return .southWest
		case .northEast: return .southEast
		case .south: return .north
		case .southWest: return .northWest
		case .southEast: return .northEast
		case .onTop: return .onTop
		}
	}
}

// MARK: - Logging

extension GameViewModel {
	func debugLog(_ message: String) {
		guard debugMode else { return }
		print("HIVE_DEBUG: \(message)")
	}
}
