//
//  HiveSpriteManager.swift
//  Hive-for-iOS
//
//  Created by Joseph Roque on 2020-03-21.
//  Copyright © 2020 Joseph Roque. All rights reserved.
//

import SpriteKit
import HiveEngine

class HiveSpriteManager {
	private(set) var pieceSprites: [Piece: SKSpriteNode] = [:]
	private(set) var positionSprites: [Position: SKSpriteNode] = [:]

	func sprite(for piece: Piece) -> SKSpriteNode {
		if let sprite = pieceSprites[piece] {
			return sprite
		}

		let sprite = SKSpriteNode(from: piece)
		sprite.name = "Piece-\(piece.notation)"
		sprite.zPosition = 1
		pieceSprites[piece] = sprite
		return sprite
	}

	func piece(from sprite: SKNode) -> Piece? {
		guard let name = sprite.name else { return nil }
		let notation = name.starts(with: "Piece-") ? name.substring(from: 6) : ""
		return Piece(notation: notation)
	}

	func sprite(for position: Position) -> SKSpriteNode {
		if let sprite = positionSprites[position] {
			return sprite
		}

		let sprite = SKSpriteNode(imageNamed: "Pieces/Blank")
		sprite.name = "Position-\(position.description)"
		sprite.position = position.point()
		resetAppearance(sprite: sprite)
		sprite.colorBlendFactor = 1
		sprite.zPosition = -1

		let positionLabel = SKLabelNode(text: position.description)
		positionLabel.name = "Label"
		positionLabel.horizontalAlignmentMode = .center
		positionLabel.verticalAlignmentMode = .center
		positionLabel.fontSize = 24
		positionLabel.position = CGPoint(x: sprite.size.width / 2, y: sprite.size.height / 2)
		positionLabel.zPosition = 1
		sprite.addChild(positionLabel)

		#warning("TODO: change text anchor point to center")

		positionSprites[position] = sprite
		return sprite
	}

	func hidePositionLabel(for position: Position, hidden: Bool) {
		let sprite = self.sprite(for: position)
		sprite.childNode(withName: "Label")?.isHidden = hidden
	}

	func resetAppearance(sprite: SKSpriteNode) {
		if sprite.name?.starts(with: "Piece-") ?? false {
			guard let piece = self.piece(from: sprite) else { return }
			sprite.color = piece.owner == .white ? UIColor(.white) : UIColor(.primary)
		} else if sprite.name?.starts(with: "Position-") ?? false {
			sprite.color = UIColor(.backgroundLight)
		}
	}
}

extension Position {
	fileprivate static var baseScale: CGPoint {
		CGPoint(x: 1, y: 1)
	}

	func point(scale: CGPoint = baseScale, offset: CGPoint = .zero) -> CGPoint {
		let q = CGFloat(x)
		let r = CGFloat(z)
		let x: CGFloat = CGFloat(3.0 / 2.0) * q
		let y: CGFloat = sqrt(CGFloat(3.0)) / 2.0 * q + sqrt(CGFloat(3.0)) * r
		return CGPoint(x: offset.x + scale.x * x, y: offset.y + scale.y * y)
	}
}

extension CGPoint {
	func position(scale: CGPoint = Position.baseScale, offset: CGPoint = .zero) -> Position {
		let x = self.x - offset.x
		let y = self.y - offset.y
		let q = Int((2 * x) / (3 * scale.x))
		let r = Int((y / (sqrt(CGFloat(3.0)) * scale.y))) - (q / 2)

		return Position(x: q, y: -r - q, z: r)
	}

	func euclideanDistance(to other: CGPoint) -> CGFloat {
		return sqrt(pow(self.x - other.x, 2) + pow(self.y - other.y, 2))
	}
}