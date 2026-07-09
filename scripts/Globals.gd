# Globals.gd — Project-wide shared assets. Registered as Autoload in
# Project Settings → Autoload. Accessible from any script as `Globals.X`.
extends Node

## The single scene used for every Kubb in the game.
const KubbScene: PackedScene = preload("res://resources/objects/kubb.tscn")

## The single scene used for every Kastpinne (baton) in the game.
const KastpinneScene: PackedScene = preload("res://resources/objects/baton.tscn")
