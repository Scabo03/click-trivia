import Foundation

extension Quiz {
    /// Il quiz integrato di esempio, a tema (ovviamente) elettrico.
    /// Ogni domanda ha la spiegazione: il valore didattico è parte del gioco.
    public static let sample: Quiz = {
        func question(
            _ text: String,
            correct: String,
            wrong: [String],
            explanation: String
        ) -> Question {
            let correctOption = AnswerOption(text: correct)
            var options = [correctOption] + wrong.map { AnswerOption(text: $0) }
            options.shuffle()
            // Dati statici già conformi agli invarianti: il try! è sicuro
            // e i test del modulo lo verificano.
            return try! Question(
                text: text,
                options: options,
                correctOptionID: correctOption.id,
                explanation: explanation
            )
        }

        return Quiz(
            title: String(localized: "Scintille di storia"),
            summary: String(localized: "Otto domande sull'elettricità e le macchine che l'hanno domata."),
            questions: [
                question(
                    "Chi inventò la pila elettrica?",
                    correct: "Alessandro Volta",
                    wrong: ["Luigi Galvani", "Michael Faraday", "Guglielmo Marconi"],
                    explanation: "Alessandro Volta presentò la sua pila nel 1800: dischi di zinco e rame separati da panni imbevuti di salamoia. Da lui prende nome il volt."
                ),
                question(
                    "Qual è l'unità di misura della resistenza elettrica?",
                    correct: "L'ohm",
                    wrong: ["Il volt", "L'ampere", "Il watt"],
                    explanation: "L'ohm, simbolo Ω, prende il nome da Georg Ohm, che nel 1827 formulò la legge che lega tensione, corrente e resistenza."
                ),
                question(
                    "Che cosa trasforma una dinamo?",
                    correct: "Energia meccanica in energia elettrica",
                    wrong: [
                        "Energia elettrica in energia meccanica",
                        "Energia chimica in energia elettrica",
                        "Energia luminosa in energia elettrica",
                    ],
                    explanation: "La dinamo sfrutta l'induzione elettromagnetica: facendo ruotare una spira in un campo magnetico, il movimento diventa corrente."
                ),
                question(
                    "Quale di questi materiali è un buon conduttore di elettricità?",
                    correct: "Il rame",
                    wrong: ["Il vetro", "Il legno secco", "La gomma"],
                    explanation: "Il rame ha elettroni liberi che si muovono facilmente: per questo i fili elettrici sono quasi sempre di rame. Vetro, legno e gomma sono isolanti."
                ),
                question(
                    "Chi scoprì l'induzione elettromagnetica?",
                    correct: "Michael Faraday",
                    wrong: ["Thomas Edison", "André-Marie Ampère", "James Watt"],
                    explanation: "Nel 1831 Faraday mostrò che un campo magnetico variabile genera corrente: è il principio di dinamo, alternatori e trasformatori."
                ),
                question(
                    "Chi fu il grande promotore della corrente alternata?",
                    correct: "Nikola Tesla",
                    wrong: ["Thomas Edison", "Benjamin Franklin", "Heinrich Hertz"],
                    explanation: "Tesla sviluppò motori e sistemi in corrente alternata; con Westinghouse vinse la 'guerra delle correnti' contro la continua di Edison."
                ),
                question(
                    "In un circuito, a che cosa serve l'interruttore?",
                    correct: "Ad aprire e chiudere il circuito",
                    wrong: [
                        "Ad aumentare la tensione",
                        "A trasformare la corrente in calore",
                        "A misurare la corrente",
                    ],
                    explanation: "Un interruttore chiuso completa il circuito e lascia passare la corrente; aperto, lo interrompe. È l'idea che dà il ritmo a questo gioco."
                ),
                question(
                    "Chi inventò il parafulmine?",
                    correct: "Benjamin Franklin",
                    wrong: ["Isaac Newton", "Antonio Meucci", "Alessandro Cruto"],
                    explanation: "Franklin, dopo i suoi studi sui fulmini del 1752, propose l'asta metallica collegata a terra che protegge gli edifici dalle scariche."
                ),
            ]
        )
    }()
}
