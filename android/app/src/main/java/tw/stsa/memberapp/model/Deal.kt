package tw.stsa.memberapp.model

import androidx.annotation.DrawableRes
import tw.stsa.memberapp.R
import java.time.LocalDate

/**
 * A partner offer for STSA members.
 *
 * The mock assumed one shared member code across every merchant. The real
 * offers each carry their own code, and some carry none at all — HSBC is an
 * information partnership, not a discount. So [code] is optional and belongs
 * to the deal rather than to the member.
 *
 * The copy below is the partners' own, in Chinese only. It is not in
 * strings.xml because it is not in the iOS string catalogue either: nobody has
 * translated a partner's terms, and inventing an English version of a
 * contractual condition would be worse than showing the original.
 */
data class Deal(
    /**
     * Partner logo, from stsa.tw's own uploads. These are horizontal lockups,
     * so they are letterboxed rather than cropped to a square.
     */
    @param:DrawableRes val logo: Int,
    val brand: String,
    val brandEnglish: String? = null,
    /** Short headline, e.g. "85 折". Null when the offer is not a discount. */
    val headline: String? = null,
    val summary: String,
    val terms: List<String>,
    val code: String? = null,
    /** Absent when the offer has no stated end date. */
    val expires: LocalDate? = null,
    /**
     * Where the offer is actually claimed, when that is a website rather than
     * showing the card in person. Drives the detail screen's primary action.
     */
    val link: String? = null,
    /** Names that action, since "開戶資訊" and "前往官網" are not interchangeable. */
    val linkTitle: String? = null,
) {
    val id: String get() = brand

    /**
     * Deals expire quietly; showing an expired code as if it works is worse
     * than hiding it.
     *
     * The end date counts as expired from its own midnight, matching iOS —
     * `expiryLabel` renders the same date as "至 2026/6/30", which reads as
     * inclusive. Pinned as current behaviour in both test suites: if the intent
     * is to keep the code usable all day, this is the line to change, and the
     * expectations named after it are what will tell you.
     */
    fun hasExpired(today: LocalDate = LocalDate.now()): Boolean {
        val end = expires ?: return false
        return !today.isBefore(end)
    }

    companion object {
        val samples: List<Deal> = listOf(
            Deal(
                logo = R.drawable.bluebird_logo,
                brand = "青鳥旅行",
                brandEnglish = "Bluebird Travel",
                headline = "85 折",
                summary = "實體門市出示會員證享 85 折，官網另有專屬折扣碼。",
                terms = listOf(
                    "實體門市出示會員證享 85 折，不與現場其他優惠活動共用",
                    "官網折扣碼不與其他優惠活動共用",
                    "實體門市暫無使用期限",
                ),
                code = "15OFF4STSA",
                expires = LocalDate.of(2026, 6, 30),
            ),
            Deal(
                logo = R.drawable.finetable_logo,
                brand = "良人食堂",
                brandEnglish = "Finetable",
                headline = "9 折",
                summary = "全站 9 折，最低消費 \$60，可與免運折扣一起使用。",
                terms = listOf(
                    "最低消費 \$60",
                    "可與免運折扣一起使用",
                    "每人不限使用次數",
                    "除禮品卡外，其他商品皆可使用",
                ),
                code = "ONLYFORSTSA",
            ),
            Deal(
                logo = R.drawable.hsbc_logo,
                brand = "HSBC 滙豐 Premier",
                brandEnglish = "全球留學理財好夥伴",
                summary = "為留學生與家庭提供全球金融服務，出發前即可開立海外帳戶，抵達後立即啟用。",
                terms = listOf(
                    "出發前即可開立海外帳戶，抵達當地後立即啟用",
                    "全球帳戶連結，跨國轉帳快速安全，即時查詢匯率",
                    "多幣種帳戶支援多達 11 種貨幣，海外提款手續費優惠",
                    "多層級換匯優惠方案",
                    "新加坡開戶需準備：身分證明文件（如護照）、現居地址證明",
                ),
                link = "https://www.hsbc.com.sg/employee-workplace/partners/sap/?cid=STSA",
                linkTitle = "開戶資訊",
            ),
        )
    }
}
