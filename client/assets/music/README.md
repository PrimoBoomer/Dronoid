# Musique d'ambiance — CC0

Dépose ici des fichiers `.ogg`, `.mp3` ou `.wav`. L'autoload `Music`
(`scripts/music_player.gd`) scanne ce dossier au lancement et lit les pistes
en shuffle, sans interruption entre les scènes.

## Sources CC0 recommandées

Toutes les pistes ci-dessous sont **CC0 / Public Domain** (aucune attribution
requise) et conviennent à un fond stellaire calme.

### Kenney — Music Jingles & Sci-Fi Sounds (CC0)
- https://kenney.nl/assets/music-jingles
- https://kenney.nl/assets/sci-fi-sounds (drones, beds)
- Pack ZIP, prend les `.ogg` longs comme nappes.

### OpenGameArt — collections "Public Domain (CC0)"
- "CC0 - Calm / Relaxing Music" : https://opengameart.org/content/cc0-calm-relaxing-music
- "Space Background Music" : https://opengameart.org/content/space-background-music
- "CC0 Background Ambience" : https://opengameart.org/content/cc0-background-ambience
- Filtre OGA par licence "CC0" : https://opengameart.org/art-search?field_art_tags_tid_op=or&field_art_tags_tid=ambient+space&field_art_type_tid%5B%5D=12&sort_by=count&field_art_licenses_tid%5B%5D=4

### Freesound — exemples directs CC0
- "Sci-fi Ambient Drone" par LookIMadeAThing : https://freesound.org/people/LookIMadeAThing/sounds/534018/
- "Drone Loop (Fixed)" par Fission9 : https://freesound.org/people/Fission9/sounds/567220/
- "Complex shifting ambient drone 1" par +frame+ : https://freesound.org/people/+frame+/sounds/837364/
- "Quasi Drone" par bassimat : https://freesound.org/people/bassimat/sounds/840934/

> ⚠️ Vérifie systématiquement la licence sur la page Freesound : sélectionne
> uniquement celles marquées **Creative Commons 0** dans le filtre. Les
> "Attribution" / "Attribution-NonCommercial" sont à éviter sans crédit visible.

## Format conseillé

- **OGG Vorbis** (poids/qualité) — Godot l'importe directement avec boucle.
- 2–5 minutes par piste, déposées en plusieurs fichiers : l'autoload joue en
  shuffle. Pas besoin de pré-bouclage : la fin enchaîne sur la suivante.

## Volume

Ajusté à `-10 dB` par défaut dans `music_player.gd` (`VOLUME_DB`). Modifie
cette constante si trop fort/faible.
