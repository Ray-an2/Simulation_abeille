# Simulation_abeille

## Introduction

Simulation en 3D du recrutement chez les abeilles par la danse. Des butineuses explorent des sources de nectar (fleurs), reviennent à la ruche et dansent pour indiquer aux autres abeilles où se trouvent les meilleures sources. La simulation met en évidence les boucles de rétroaction (positives et négatives) qui régulent ce comportement collectif.

## Contenu du modèle 3D

- 1 ruche (orange)
- De 20 à 200 abeilles ouvrières, avec 2 états :
  - en attente (jaune)
  - suivre la danseuse (couleur de la source)
- 3 types de fleurs (bleu / rouge / violet), avec 10 fleurs de chaque type

## Entité

### Ruche

Point de départ et de retour des butineuses. C'est là que le nectar est déchargé et que les danses de recrutement ont lieu. Représentée en orange.

### Abeille

Abeille ouvrière (entre 20 et 200 dans la simulation). Elle possède deux états :

| État | Couleur |
|------|---------|
| En attente | Jaune |
| Suivre la danseuse | Couleur de la source |

### Fleurs

Trois types de fleurs, avec 10 fleurs de chaque type :

- Bleue
- Rouge
- Violette

Chaque fleur constitue une source de nectar qui peut s'épuiser.

## Interactions

### Boucle positive

**Recrutement** : une butineuse trouve une source riche (+) → elle danse plus longtemps à son retour (+) → plus d'abeilles sont recrutées vers cette source (+) → plus de butineuses y vont et rapportent du nectar (+) → plus de danses.

*Contexte* : la danse encode la direction (angle par rapport au soleil) et la distance (durée de la phase frétillante). Plus la source est rentable, plus l'abeille danse, ce qui amplifie le signal.

### Boucles négatives

- **Épuisement de la source** : plus de butineuses (+) → la fleur ou le champ se vide plus vite (+) → source moins rentable (−) → danses plus courtes (−) → moins de recrues.
- **Saturation de la ruche** : beaucoup de nectar rapporté (+) → peu de receveuses disponibles, attente plus longue pour décharger (+) → les butineuses dansent moins (−) → moins de recrutement.
- **Concurrence entre sources** : une meilleure source attire les abeilles au détriment des moins bonnes, qui sont abandonnées.

## Fin de la simulation

La simulation se termine s'il n'y a plus de source disponible.

## Crédit

On remercie :
- laanita "Lily" (lys blanche)
- GardenBee "Rose Red" (Rose rouge) et "Rose Blue" (Rose bleu)
