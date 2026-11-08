from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parents[2]
PDF = ROOT / "output" / "pdf" / "Guide_complet_du_projet_StudentHub.pdf"
APPENDIX = ROOT / "tmp" / "pdfs" / "studenthub_email_appendix.pdf"

NAVY = colors.HexColor("#17324D")
BLUE = colors.HexColor("#2F8FE5")
PALE = colors.HexColor("#EEF6FC")
TEXT = colors.HexColor("#24364B")
MUTED = colors.HexColor("#62758B")
GREEN = colors.HexColor("#198754")
AMBER = colors.HexColor("#A76A0A")

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="DocTitle", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=23, leading=27, textColor=NAVY, alignment=TA_LEFT, spaceAfter=6))
styles.add(ParagraphStyle(name="Deck", parent=styles["Normal"], fontSize=10, leading=15, textColor=MUTED, spaceAfter=12))
styles.add(ParagraphStyle(name="Section", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=14, leading=18, textColor=NAVY, spaceBefore=8, spaceAfter=7))
styles.add(ParagraphStyle(name="Subsection", parent=styles["Heading3"], fontName="Helvetica-Bold", fontSize=10.5, leading=14, textColor=NAVY, spaceBefore=5, spaceAfter=4))
styles.add(ParagraphStyle(name="Body2", parent=styles["BodyText"], fontSize=9, leading=13.2, textColor=TEXT, spaceAfter=6))
styles.add(ParagraphStyle(name="Small", parent=styles["BodyText"], fontSize=8, leading=11, textColor=MUTED, spaceAfter=4))
styles.add(ParagraphStyle(name="StepTitle", parent=styles["BodyText"], fontName="Helvetica-Bold", fontSize=9.4, leading=12, textColor=NAVY, spaceAfter=3))
styles.add(ParagraphStyle(name="CodeBlock", fontName="Courier", fontSize=7.4, leading=10, textColor=colors.HexColor("#EAF3FB"), backColor=colors.HexColor("#15293B"), borderPadding=8, leftIndent=0, rightIndent=0, spaceBefore=3, spaceAfter=7))
styles.add(ParagraphStyle(name="Callout", parent=styles["BodyText"], fontSize=8.5, leading=12, textColor=TEXT, borderPadding=8, spaceBefore=4, spaceAfter=7))


def footer(canvas, doc):
    canvas.saveState()
    width, _ = A4
    canvas.setStrokeColor(colors.HexColor("#DFE8F0"))
    canvas.line(18 * mm, 15 * mm, width - 18 * mm, 15 * mm)
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(18 * mm, 10 * mm, "STUDENTHUB  /  COURRIELS ET VERIFICATION")
    canvas.drawRightString(width - 18 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


def callout(text, background=PALE, accent=BLUE):
    p = Paragraph(text, styles["Callout"])
    t = Table([[p]], colWidths=[174 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), background),
        ("LINEBEFORE", (0, 0), (0, -1), 3, accent),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    return t


doc = SimpleDocTemplate(
    str(APPENDIX), pagesize=A4,
    rightMargin=18 * mm, leftMargin=18 * mm,
    topMargin=17 * mm, bottomMargin=21 * mm,
    title="StudentHub - verification par e-mail avec Resend",
    author="StudentHub",
)
story = []

story += [
    Paragraph("Verification par e-mail", styles["DocTitle"]),
    Paragraph("Inscription StudentHub, codes de confirmation et service Resend", styles["Deck"]),
    callout("<b>Ce qui est implemente :</b> l'application demande un code a six chiffres a l'inscription, le verifie, conserve l'etat dans SQLite et affiche le badge <b>Verifie</b> sur le profil. Les comptes valides attendent ensuite l'approbation de l'administrateur.", background=colors.HexColor("#E8F7EF"), accent=GREEN),
    Spacer(1, 4 * mm),
    Paragraph("Parcours dans l'application", styles["Section"]),
]

steps = [
    [Paragraph("1  Inscription", styles["StepTitle"]), Paragraph("Le compte est cree dans la base SQLite de l'appareil avec l'e-mail non verifie et le statut en attente.", styles["Small"])],
    [Paragraph("2  Code e-mail", styles["StepTitle"]), Paragraph("Le serveur Node envoie un code avec Resend. Le code expire apres 10 minutes et les essais sont limites.", styles["Small"])],
    [Paragraph("3  Confirmation", styles["StepTitle"]), Paragraph("L'application confirme le code au serveur puis marque l'adresse comme verifiee dans SQLite.", styles["Small"])],
    [Paragraph("4  Approbation admin", styles["StepTitle"]), Paragraph("L'administrateur valide ou bloque les comptes locaux. Seuls les comptes verifies et valides peuvent se connecter.", styles["Small"])],
]
table = Table(steps, colWidths=[37 * mm, 137 * mm], rowHeights=[24 * mm] * 4)
table.setStyle(TableStyle([
    ("BACKGROUND", (0, 0), (0, -1), PALE),
    ("BACKGROUND", (1, 0), (1, -1), colors.white),
    ("BOX", (0, 0), (-1, -1), 0.7, colors.HexColor("#DCE7F0")),
    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DCE7F0")),
    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ("LEFTPADDING", (0, 0), (-1, -1), 8),
    ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ("TOPPADDING", (0, 0), (-1, -1), 5),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
]))
story += [table, Spacer(1, 4 * mm), Paragraph("Architecture actuelle", styles["Section"])]
story += [
    Paragraph("<b>Flutter</b> appelle les routes du service Node a l'adresse definie par <font name='Courier'>ACCOUNT_API_URL</font>. Le serveur utilise la cle Resend, conserve les codes temporairement en memoire et appelle l'API Resend. La cle ne doit jamais etre ajoutee au code Flutter.", styles["Body2"]),
    Paragraph("<b>SQLite reste local a chaque appareil.</b> L'ecran Gestion des comptes ne voit que les comptes presents dans la base de l'appareil administrateur. Pour une vraie administration partagee entre utilisateurs, il faudra une base serveur commune.", styles["Body2"]),
    PageBreak(),
    Paragraph("Configurer Resend et lancer", styles["DocTitle"]),
    Paragraph("Guide de mise en route pour l'envoi des codes de verification", styles["Deck"]),
    Paragraph("1. Compte et expediteur Resend", styles["Section"]),
    Paragraph("Creez une cle API dans Resend. Ajoutez un domaine d'envoi que vous possedez et terminez sa verification DNS, puis utilisez une adresse sur ce domaine comme expediteur. La cle API est secrete et doit rester cote serveur.", styles["Body2"]),
    callout("Pour un essai, <font name='Courier'>onboarding@resend.dev</font> est reserve a l'envoi vers l'adresse associee au compte Resend. Pour les inscriptions d'autres personnes, configurez un domaine verifie dans Resend.", background=colors.HexColor("#FFF5E5"), accent=colors.HexColor("#E1A331")),
    Paragraph("2. Variables privees du serveur", styles["Section"]),
    Paragraph("Copiez le modele <font name='Courier'>backend/.env.example</font> vers <font name='Courier'>backend/.env</font>, puis completez les valeurs. Le fichier prive est ignore par Git.", styles["Body2"]),
    Preformatted("PORT=6500\nRESEND_API_KEY=votre_cle_resend_complete\nRESEND_SENDER_EMAIL=welcome@votre-domaine-verifie.com\nRESEND_SENDER_NAME=StudentHub", styles["CodeBlock"]),
    Paragraph("Dans PowerShell, depuis la racine StudentHub, demarrez le service et laissez ce terminal ouvert :", styles["Body2"]),
    Preformatted("node backend/welcome_mail_server.mjs", styles["CodeBlock"]),
    Paragraph("La sortie doit annoncer le port configure. Pour un test local depuis un deuxieme terminal PowerShell :", styles["Body2"]),
    Preformatted("$body = @{ email = 'votre-email'; firstName = 'Eya' } | ConvertTo-Json -Compress\nInvoke-RestMethod -Method Post -Uri 'http://localhost:6500/verification-email' -ContentType 'application/json' -Body $body", styles["CodeBlock"]),
    Paragraph("3. Connecter l'application Android", styles["Section"]),
    Paragraph("L'application Flutter exige une URL HTTPS publique pour appeler le serveur. <font name='Courier'>localhost</font> sur l'emulateur Android designe l'emulateur lui-meme et le service local utilise HTTP : une URL HTTPS hebergee ou un tunnel HTTPS est necessaire pour ce parcours depuis l'application.", styles["Body2"]),
    Preformatted("flutter run -d emulator-5554 --dart-define=ACCOUNT_API_URL=https://votre-api.example.com", styles["CodeBlock"]),
    callout("La cle doit rester dans le fichier backend/.env, jamais dans un message, une capture d'ecran, un commit Git ou une option dart-define. Si une cle a ete partagee, revoquez-la dans Resend et remplacez-la.", background=colors.HexColor("#FDEDEC"), accent=colors.HexColor("#C44536")),
    Paragraph("En cas d'erreur HTTP, consulter le terminal Node : le serveur indique le code de refus de Resend. Un code 401 indique une cle invalide ou revoquee ; un code 422 signale une requete ou un expediteur a corriger.", styles["Small"]),
]
doc.build(story, onFirstPage=footer, onLaterPages=footer)

reader = PdfReader(str(PDF))
appendix_reader = PdfReader(str(APPENDIX))
writer = PdfWriter()
writer.append(reader)
writer.append(appendix_reader)
with PDF.open("wb") as output:
    writer.write(output)
print(f"Updated {PDF} with {len(appendix_reader.pages)} pages; total {len(writer.pages)} pages.")
