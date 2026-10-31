// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LowPowerModeFeatureStrings {
    let title: String
    let caption: String
    let adminPrompt: String
    let failed: String
    let unavailable: String
}

extension FeatureStrings {
    static func lowPowerMode(_ language: AppLanguage) -> LowPowerModeFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension LowPowerModeFeatureStrings {
    static let enUS = LowPowerModeFeatureStrings(
        title: "Low Power Mode",
        caption: "Reduces energy use for the current power source.",
        adminPrompt: "Vorssaint needs permission to change Low Power Mode.",
        failed: "Couldn’t change Low Power Mode. Try again.",
        unavailable: "Low Power Mode is unavailable on this Mac."
    )

    static let ptBR = LowPowerModeFeatureStrings(
        title: "Modo de Pouca Energia",
        caption: "Reduz o consumo de energia na fonte de alimentação atual.",
        adminPrompt: "O Vorssaint precisa de permissão para alterar o Modo de Pouca Energia.",
        failed: "Não foi possível alterar o Modo de Pouca Energia. Tente novamente.",
        unavailable: "O Modo de Pouca Energia não está disponível neste Mac."
    )

    static let tr = LowPowerModeFeatureStrings(
        title: "Düşük Güç Modu",
        caption: "Geçerli güç kaynağında enerji kullanımını azaltır.",
        adminPrompt: "Vorssaint, Düşük Güç Modu’nu değiştirmek için izin istiyor.",
        failed: "Düşük Güç Modu değiştirilemedi. Tekrar deneyin.",
        unavailable: "Düşük Güç Modu bu Mac’te kullanılamıyor."
    )

    static let ru = LowPowerModeFeatureStrings(
        title: "Режим энергосбережения",
        caption: "Снижает расход энергии при текущем источнике питания.",
        adminPrompt: "Vorssaint требуется разрешение на изменение режима энергосбережения.",
        failed: "Не удалось изменить режим энергосбережения. Повторите попытку.",
        unavailable: "Режим энергосбережения недоступен на этом Mac."
    )

    static let es = LowPowerModeFeatureStrings(
        title: "Modo de bajo consumo",
        caption: "Reduce el consumo de energía con la fuente de alimentación actual.",
        adminPrompt: "Vorssaint necesita permiso para cambiar el modo de bajo consumo.",
        failed: "No se pudo cambiar el modo de bajo consumo. Inténtalo de nuevo.",
        unavailable: "El modo de bajo consumo no está disponible en este Mac."
    )

    static let sk = LowPowerModeFeatureStrings(
        title: "Režim nízkej spotreby",
        caption: "Znižuje spotrebu energie pri aktuálnom zdroji napájania.",
        adminPrompt: "Vorssaint potrebuje povolenie na zmenu režimu nízkej spotreby.",
        failed: "Režim nízkej spotreby sa nepodarilo zmeniť. Skúste to znova.",
        unavailable: "Režim nízkej spotreby nie je na tomto Macu dostupný."
    )

    static let de = LowPowerModeFeatureStrings(
        title: "Stromsparmodus",
        caption: "Reduziert den Energieverbrauch für die aktuelle Stromquelle.",
        adminPrompt: "Vorssaint benötigt die Erlaubnis, den Stromsparmodus zu ändern.",
        failed: "Der Stromsparmodus konnte nicht geändert werden. Versuche es erneut.",
        unavailable: "Der Stromsparmodus ist auf diesem Mac nicht verfügbar."
    )

    static let fr = LowPowerModeFeatureStrings(
        title: "Mode économie d’énergie",
        caption: "Réduit la consommation d’énergie avec la source d’alimentation actuelle.",
        adminPrompt: "Vorssaint a besoin de votre autorisation pour modifier le mode économie d’énergie.",
        failed: "Impossible de modifier le mode économie d’énergie. Réessayez.",
        unavailable: "Le mode économie d’énergie n’est pas disponible sur ce Mac."
    )

    static let it = LowPowerModeFeatureStrings(
        title: "Risparmio energetico",
        caption: "Riduce il consumo energetico con la fonte di alimentazione attuale.",
        adminPrompt: "Vorssaint richiede l’autorizzazione per modificare il risparmio energetico.",
        failed: "Impossibile modificare il risparmio energetico. Riprova.",
        unavailable: "Il risparmio energetico non è disponibile su questo Mac."
    )

    static let ja = LowPowerModeFeatureStrings(
        title: "低電力モード",
        caption: "現在の電源での消費電力を抑えます。",
        adminPrompt: "低電力モードを変更するには、Vorssaintへの許可が必要です。",
        failed: "低電力モードを変更できませんでした。もう一度お試しください。",
        unavailable: "このMacでは低電力モードを利用できません。"
    )

    static let ko = LowPowerModeFeatureStrings(
        title: "저전력 모드",
        caption: "현재 전원에서 에너지 사용량을 줄입니다.",
        adminPrompt: "저전력 모드를 변경하려면 Vorssaint에 권한이 필요합니다.",
        failed: "저전력 모드를 변경할 수 없습니다. 다시 시도하세요.",
        unavailable: "이 Mac에서는 저전력 모드를 사용할 수 없습니다."
    )

    static let uk = LowPowerModeFeatureStrings(
        title: "Режим низького заряду",
        caption: "Зменшує споживання енергії за поточного джерела живлення.",
        adminPrompt: "Vorssaint потрібен дозвіл на зміну режиму низького заряду.",
        failed: "Не вдалося змінити режим низького заряду. Спробуйте ще раз.",
        unavailable: "Режим низького заряду недоступний на цьому Mac."
    )

    static let zhHans = LowPowerModeFeatureStrings(
        title: "低电量模式",
        caption: "降低当前供电方式下的能耗。",
        adminPrompt: "Vorssaint 需要获得许可才能更改低电量模式。",
        failed: "无法更改低电量模式，请重试。",
        unavailable: "此 Mac 不支持低电量模式。"
    )

    static let zhTW = LowPowerModeFeatureStrings(
        title: "低耗電模式",
        caption: "降低目前電源下的耗電量。",
        adminPrompt: "Vorssaint 需要取得許可才能更改低耗電模式。",
        failed: "無法更改低耗電模式，請再試一次。",
        unavailable: "此 Mac 不支援低耗電模式。"
    )

    static let zhHK = LowPowerModeFeatureStrings(
        title: "低耗電模式",
        caption: "減少目前電源下的耗電量。",
        adminPrompt: "Vorssaint 需要取得許可才能更改低耗電模式。",
        failed: "無法更改低耗電模式，請再試一次。",
        unavailable: "此 Mac 不支援低耗電模式。"
    )
}
