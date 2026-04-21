#!/usr/bin/env python3
"""Regenerate taxonomy.json with description_pt / description_en / description_es.

Run from repo root: python3 scripts/build_taxonomy_descriptions.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "EgoCapture/Resources/taxonomy.json"

DOC = {
    "pt": "Taxonomia hierárquica de 5 níveis para classificação de vídeos egocêntricos. Baseada em padrões de mercado (Ego4D, EPIC-KITCHENS, Ego-Exo4D, HoloAssist).",
    "en": "Five-level hierarchical taxonomy for classifying egocentric videos. Based on market standards (Ego4D, EPIC-KITCHENS, Ego-Exo4D, HoloAssist).",
    "es": "Taxonomía jerárquica de cinco niveles para clasificar videos egocéntricos. Basada en estándares del sector (Ego4D, EPIC-KITCHENS, Ego-Exo4D, HoloAssist).",
}

VIEWPOINTS = [
    ("egocentric", "Egocêntrica", "Egocentric", {
        "pt": "Câmera em primeira pessoa (head-mounted, chest-mounted, glasses)",
        "en": "First-person camera (head-mounted, chest-mounted, glasses)",
        "es": "Cámara en primera persona (montada en la cabeza, pecho o gafas)",
    }),
    ("exocentric", "Exocêntrica", "Exocentric", {
        "pt": "Câmera em terceira pessoa (fixa, tripé, observador)",
        "en": "Third-person camera (fixed, tripod, observer)",
        "es": "Cámara en tercera persona (fija, trípode, observador)",
    }),
    ("hybrid", "Híbrida", "Hybrid", {
        "pt": "Múltiplas câmeras sincronizadas (ego + exo) — padrão Ego-Exo4D",
        "en": "Multiple synchronized cameras (ego + exo) — Ego-Exo4D pattern",
        "es": "Múltiples cámaras sincronizadas (ego + exo) — patrón Ego-Exo4D",
    }),
]

DOMAINS = [
    ("residential", "Residencial", "Residential", {
        "pt": "Casa, apartamento, AirBnB",
        "en": "House, apartment, AirBnB",
        "es": "Casa, apartamento, AirBnB",
    }),
    ("commercial", "Comercial", "Commercial", {
        "pt": "Restaurante, loja, escritório, pet shop",
        "en": "Restaurant, retail, office, pet shop",
        "es": "Restaurante, tienda, oficina, tienda de mascotas",
    }),
    ("industrial", "Industrial", "Industrial", {
        "pt": "Fábrica, oficina, armazém",
        "en": "Factory, workshop, warehouse",
        "es": "Fábrica, taller, almacén",
    }),
    ("institutional", "Institucional", "Institutional", {
        "pt": "Escola, hospital, repartição pública",
        "en": "School, hospital, government office",
        "es": "Escuela, hospital, oficina pública",
    }),
    ("public_outdoor", "Espaço Público Externo", "Public Outdoor", {
        "pt": "Rua, parque, praça",
        "en": "Street, park, plaza",
        "es": "Calle, parque, plaza",
    }),
    ("transport", "Transporte", "Transport", {
        "pt": "Veículo, transporte público, aeroporto",
        "en": "Vehicle, public transit, airport",
        "es": "Vehículo, transporte público, aeropuerto",
    }),
]

SCENARIOS = [
    ("indoor", "Interno", "Indoor", {
        "pt": "Totalmente dentro de estrutura fechada",
        "en": "Fully inside an enclosed structure",
        "es": "Completamente dentro de una estructura cerrada",
    }),
    ("outdoor", "Externo", "Outdoor", {
        "pt": "Totalmente ao ar livre",
        "en": "Fully outdoors",
        "es": "Completamente al aire libre",
    }),
    ("semi_outdoor", "Semi-externo", "Semi-outdoor", {
        "pt": "Varanda coberta, garagem aberta, quiosque",
        "en": "Covered porch, open garage, kiosk",
        "es": "Porche cubierto, garaje abierto, quiosco",
    }),
    ("transition", "Transição", "Transition", {
        "pt": "Passagem entre ambientes (ex: saindo de casa)",
        "en": "Moving between environments (e.g. leaving home)",
        "es": "Transición entre entornos (p. ej., salir de casa)",
    }),
]

# task_category code -> (pt, en, es)
TASK_DESC: dict[str, dict[str, str]] = {
    "cleaning": {
        "pt": "Remover sujeira de superfícies, objetos, ambientes",
        "en": "Remove dirt from surfaces, objects, and spaces",
        "es": "Eliminar suciedad de superficies, objetos y espacios",
    },
    "tidying": {
        "pt": "Arrumar, guardar, posicionar objetos sem necessariamente limpar",
        "en": "Tidy, store, and place objects without necessarily cleaning",
        "es": "Ordenar, guardar y colocar objetos sin necesidad de limpiar",
    },
    "laundry": {
        "pt": "Coletar, lavar, secar, dobrar, guardar roupas",
        "en": "Collect, wash, dry, fold, and put away laundry",
        "es": "Recoger, lavar, secar, doblar y guardar la ropa",
    },
    "dishwashing": {
        "pt": "Lavar utensílios e louças",
        "en": "Wash utensils and dishes",
        "es": "Lavar utensilios y vajilla",
    },
    "waste_management": {
        "pt": "Separar, descartar, levar lixo",
        "en": "Sort, dispose of, and take out trash",
        "es": "Separar, desechar y sacar la basura",
    },
    "food_preparation": {
        "pt": "Separar, lavar, cortar, medir ingredientes (antes do cozimento)",
        "en": "Separate, wash, cut, and measure ingredients (before cooking)",
        "es": "Separar, lavar, cortar y medir ingredientes (antes de cocinar)",
    },
    "cooking": {
        "pt": "Aplicar calor — fogão, forno, micro-ondas, grelha",
        "en": "Apply heat — stove, oven, microwave, grill",
        "es": "Aplicar calor — fogón, horno, microondas, parrilla",
    },
    "baking": {
        "pt": "Subcategoria de cooking — assar no forno",
        "en": "Cooking subcategory — baking in the oven",
        "es": "Subcategoría de cocción — hornear en el horno",
    },
    "food_serving": {
        "pt": "Empratar, servir, montar mesa",
        "en": "Plate, serve, and set the table",
        "es": "Emplatar, servir y poner la mesa",
    },
    "eating": {
        "pt": "Comer, beber, degustar",
        "en": "Eat, drink, and taste",
        "es": "Comer, beber y degustar",
    },
    "beverage_preparation": {
        "pt": "Café, suco, drinks",
        "en": "Coffee, juice, mixed drinks",
        "es": "Café, zumo, bebidas mixtas",
    },
    "personal_care": {
        "pt": "Banho, escovar dentes, maquiagem, vestir-se",
        "en": "Bathing, brushing teeth, makeup, getting dressed",
        "es": "Baño, cepillarse los dientes, maquillaje, vestirse",
    },
    "grooming": {
        "pt": "Pentear, barbear, cortar unhas",
        "en": "Combing hair, shaving, trimming nails",
        "es": "Peinarse, afeitarse, cortarse las uñas",
    },
    "health_care": {
        "pt": "Tomar medicamento, aferir pressão, curativo",
        "en": "Take medication, measure blood pressure, apply bandages",
        "es": "Tomar medicación, medir la tensión, vendajes",
    },
    "childcare": {
        "pt": "Alimentar, vestir, brincar, banho de criança",
        "en": "Feed, dress, play with, and bathe a child",
        "es": "Alimentar, vestir, jugar y bañar a un niño",
    },
    "eldercare": {
        "pt": "Assistência a idosos, mobilidade, medicação",
        "en": "Assisting older adults, mobility, medication",
        "es": "Asistencia a mayores, movilidad, medicación",
    },
    "pet_care": {
        "pt": "Alimentar, banhar, passear, brincar com pet",
        "en": "Feed, bathe, walk, and play with a pet",
        "es": "Alimentar, bañar, pasear y jugar con una mascota",
    },
    "pet_training": {
        "pt": "Comandos, reforço positivo, socialização",
        "en": "Commands, positive reinforcement, socialization",
        "es": "Comandos, refuerzo positivo, socialización",
    },
    "plant_care": {
        "pt": "Regar, podar, adubar plantas domésticas",
        "en": "Water, prune, and fertilize houseplants",
        "es": "Regar, podar y abonar plantas de interior",
    },
    "gardening": {
        "pt": "Cultivo, paisagismo, horta externa",
        "en": "Growing plants, landscaping, outdoor vegetable garden",
        "es": "Cultivo, paisajismo, huerto exterior",
    },
    "maintenance": {
        "pt": "Consertar, trocar peças, lubrificar",
        "en": "Repair, replace parts, lubricate",
        "es": "Reparar, cambiar piezas, lubricar",
    },
    "repair": {
        "pt": "Subcategoria de maintenance — consertos específicos",
        "en": "Maintenance subcategory — specific fixes",
        "es": "Subcategoría de mantenimiento — reparaciones concretas",
    },
    "assembly": {
        "pt": "Montar móveis, brinquedos, kits",
        "en": "Assemble furniture, toys, and kits",
        "es": "Montar muebles, juguetes y kits",
    },
    "crafting": {
        "pt": "Artesanato, costura, tricô, DIY",
        "en": "Crafts, sewing, knitting, DIY",
        "es": "Manualidades, costura, punto, bricolaje",
    },
    "shopping": {
        "pt": "Selecionar produtos, checkout, carregar compras",
        "en": "Select products, checkout, carry bags",
        "es": "Elegir productos, pagar, cargar bolsas",
    },
    "carrying": {
        "pt": "Carregar, mover objetos entre locais",
        "en": "Carry and move objects between places",
        "es": "Cargar y mover objetos entre lugares",
    },
    "driving": {
        "pt": "Operar veículo",
        "en": "Operate a vehicle",
        "es": "Conducir un vehículo",
    },
    "commuting": {
        "pt": "Caminhada, transporte entre locais",
        "en": "Walking, traveling between locations",
        "es": "Caminar, desplazarse entre lugares",
    },
    "communication": {
        "pt": "Conversar, telefonar, videochamada",
        "en": "Talking, phone calls, video calls",
        "es": "Conversar, llamadas, videollamadas",
    },
    "socializing": {
        "pt": "Conversas em grupo, recepção de visitas",
        "en": "Group conversations, hosting guests",
        "es": "Conversaciones en grupo, recibir visitas",
    },
    "working_desk": {
        "pt": "Computador, leitura, escrita, reunião",
        "en": "Computer work, reading, writing, meetings",
        "es": "Ordenador, lectura, escritura, reuniones",
    },
    "studying": {
        "pt": "Leitura, anotações, exercícios",
        "en": "Reading, notes, exercises",
        "es": "Lectura, apuntes, ejercicios",
    },
    "leisure": {
        "pt": "TV, jogos, relaxamento",
        "en": "TV, games, relaxation",
        "es": "TV, juegos, relaxación",
    },
    "exercise": {
        "pt": "Musculação, cardio, alongamento",
        "en": "Strength training, cardio, stretching",
        "es": "Musculación, cardio, estiramientos",
    },
    "sports": {
        "pt": "Esportes específicos (futebol, tênis, etc.)",
        "en": "Specific sports (soccer, tennis, etc.)",
        "es": "Deportes concretos (fútbol, tenis, etc.)",
    },
    "music_practice": {
        "pt": "Tocar instrumento, cantar",
        "en": "Playing an instrument, singing",
        "es": "Tocar un instrumento, cantar",
    },
}


def main() -> None:
    data = json.loads(OUT.read_text(encoding="utf-8"))

    if "description" in data:
        del data["description"]
    # Root document blurbs — keep keys adjacent to `generated_at` for readability.
    data["description_pt"] = DOC["pt"]
    data["description_en"] = DOC["en"]
    data["description_es"] = DOC["es"]

    data["viewpoints"] = [
        {
            "code": c,
            "label_pt": lpt,
            "label_en": len_,
            "description_pt": d["pt"],
            "description_en": d["en"],
            "description_es": d["es"],
        }
        for c, lpt, len_, d in VIEWPOINTS
    ]
    data["domains"] = [
        {
            "code": c,
            "label_pt": lpt,
            "label_en": len_,
            "description_pt": d["pt"],
            "description_en": d["en"],
            "description_es": d["es"],
        }
        for c, lpt, len_, d in DOMAINS
    ]
    data["scenarios"] = [
        {
            "code": c,
            "label_pt": lpt,
            "label_en": len_,
            "description_pt": d["pt"],
            "description_en": d["en"],
            "description_es": d["es"],
        }
        for c, lpt, len_, d in SCENARIOS
    ]

    new_tasks = []
    for t in data["task_categories"]:
        code = t["code"]
        desc = TASK_DESC[code]
        new_tasks.append(
            {
                "code": code,
                "label_pt": t["label_pt"],
                "label_en": t["label_en"],
                "description_pt": desc["pt"],
                "description_en": desc["en"],
                "description_es": desc["es"],
                "group": t["group"],
            }
        )
    data["task_categories"] = new_tasks

    # Emit with a stable, human-friendly key order (root doc blurbs after metadata).
    ordered = {
        "schema_version": data["schema_version"],
        "generated_at": data["generated_at"],
        "description_pt": data["description_pt"],
        "description_en": data["description_en"],
        "description_es": data["description_es"],
        "levels": data["levels"],
        "viewpoints": data["viewpoints"],
        "domains": data["domains"],
        "scenarios": data["scenarios"],
        "locations": data["locations"],
        "task_categories": data["task_categories"],
    }
    OUT.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
