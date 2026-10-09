class_name HiveState extends BeeState
## Super-état « Ruche » : états où l'abeille marche sur le cadre.
## La locomotion commune (cap, vitesse, évitement) est dans CombWalker, via bee.walker.
## Ce super-état sert surtout à Bee.change_state() pour détecter les passages
## Ruche ↔ Dehors (présence dans la ruche, bourdonnement)..
