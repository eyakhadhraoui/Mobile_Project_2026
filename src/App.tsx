import { useState, type ReactNode } from "react";

type Screen =
  | "welcome"
  | "login"
  | "register"
  | "home"
  | "housing"
  | "add-property"
  | "edit-property"
  | "housing-history"
  | "property"
  | "visit"
  | "rides"
  | "ride-filters"
  | "my-rides"
  | "ride"
  | "request-detail"
  | "ride-author"
  | "ride-rating"
  | "ride-notifications"
  | "publish"
  | "publish-request"
  | "services"
  | "intervention"
  | "directory"
  | "service-requests"
  | "service-request-detail"
  | "service-review"
  | "service-notifications"
  | "pro"
  | "complaint"
  | "tracking"
  | "complaint-detail"
  | "activity"
  | "notifications"
  | "profile";

type IconName =
  | "home"
  | "building"
  | "car"
  | "tools"
  | "user"
  | "bell"
  | "search"
  | "map"
  | "heart"
  | "bed"
  | "area"
  | "arrow"
  | "calendar"
  | "clock"
  | "star"
  | "users"
  | "plus"
  | "chevron"
  | "check"
  | "camera"
  | "message"
  | "settings"
  | "help"
  | "logout"
  | "droplet"
  | "bolt"
  | "paint"
  | "key"
  | "snow"
  | "alert"
  | "eye"
  | "mail"
  | "phone"
  | "lock"
  | "swap"
  | "sliders";

const photos = {
  apartment:
    "https://images.unsplash.com/photo-1665249934445-1de680641f50?auto=format&fit=crop&w=900&q=85",
  studio:
    "https://images.unsplash.com/photo-1631510390389-c1e4fb20ff31?auto=format&fit=crop&w=900&q=85",
  loft: "https://images.unsplash.com/photo-1615529179035-e760f6a2dcee?auto=format&fit=crop&w=900&q=85",
  marsa:
    "https://images.unsplash.com/photo-1600210491369-e753d80a41f3?auto=format&fit=crop&w=900&q=85",
  pro: "https://images.unsplash.com/photo-1659353591753-dac60f2f7896?auto=format&fit=crop&w=400&q=85",
  pro2: "https://images.unsplash.com/photo-1659353587819-4621e4534dfd?auto=format&fit=crop&w=400&q=85",
};

function Icon({ name, size = 22 }: { name: IconName; size?: number }) {
  const paths: Partial<Record<IconName, ReactNode>> = {
    home: <><path d="m3 10 9-7 9 7" /><path d="M5 9v11h14V9M9 20v-6h6v6" /></>,
    building: <><rect x="4" y="3" width="16" height="18" rx="2" /><path d="M8 7h2m4 0h2M8 11h2m4 0h2M8 15h2m4 0h2M9 21v-2h6v2" /></>,
    car: <><path d="m5 17-2-2v-4l2-5h14l2 5v4l-2 2" /><path d="M5 11h14M7 15h.01M17 15h.01M6 17v2m12-2v2" /></>,
    tools: <><path d="m14 7 3-3 3 3-3 3M14 7 4 17l3 3 10-10" /><path d="m4 4 4 4M3 3l2 4 2-2-4-2Z" /></>,
    user: <><circle cx="12" cy="8" r="4" /><path d="M4 21c.6-5 3.3-7 8-7s7.4 2 8 7" /></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M10 21h4" /></>,
    search: <><circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 5 5" /></>,
    map: <><path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" /></>,
    heart: <path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.7-7.5 1.1-1.1a5.5 5.5 0 0 0 0-7.8Z" />,
    bed: <><path d="M3 18v-7h18v7M3 15h18M7 11V7h5a4 4 0 0 1 4 4" /></>,
    area: <><path d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5" /><path d="m3 8 6-5m12 5-6-5M3 16l6 5m12-5-6 5" /></>,
    arrow: <><path d="m15 18-6-6 6-6" /></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M16 3v4M8 3v4M3 10h18" /></>,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    star: <path d="m12 2 3 6 6.5.9-4.7 4.6 1.1 6.5-5.9-3.1-5.9 3.1 1.1-6.5L2.5 8.9 9 8Z" />,
    users: <><circle cx="9" cy="8" r="3" /><path d="M3 19c.3-4 2.3-6 6-6s5.7 2 6 6M16 5a3 3 0 0 1 0 6M17 14c2.5.5 3.8 2.2 4 5" /></>,
    plus: <path d="M12 5v14M5 12h14" />,
    chevron: <path d="m9 18 6-6-6-6" />,
    check: <path d="m5 12 4 4L19 6" />,
    camera: <><path d="M4 7h3l2-3h6l2 3h3v13H4Z" /><circle cx="12" cy="13" r="4" /></>,
    message: <path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4Z" />,
    settings: <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a2 2 0 0 0 .4 2.2l.1.1-2.7 2.7-.1-.1a2 2 0 0 0-2.2-.4 2 2 0 0 0-1.2 1.8V22H10v-.7a2 2 0 0 0-1.2-1.8 2 2 0 0 0-2.2.4l-.1.1-2.7-2.7.1-.1a2 2 0 0 0 .4-2.2A2 2 0 0 0 2.5 14H2v-4h.5a2 2 0 0 0 1.8-1.2 2 2 0 0 0-.4-2.2l-.1-.1 2.7-2.7.1.1a2 2 0 0 0 2.2.4A2 2 0 0 0 10 2.5V2h4v.5a2 2 0 0 0 1.2 1.8 2 2 0 0 0 2.2-.4l.1-.1 2.7 2.7-.1.1a2 2 0 0 0-.4 2.2A2 2 0 0 0 21.5 10h.5v4h-.5a2 2 0 0 0-2.1 1Z" /></>,
    help: <><circle cx="12" cy="12" r="10" /><path d="M9.3 9a3 3 0 1 1 4.5 2.6c-1.1.6-1.8 1.2-1.8 2.4M12 18h.01" /></>,
    logout: <><path d="M10 17l5-5-5-5M15 12H3M14 3h5a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-5" /></>,
    droplet: <path d="M12 2s7 7.2 7 12a7 7 0 0 1-14 0c0-4.8 7-12 7-12Z" />,
    bolt: <path d="m13 2-8 12h7l-1 8 8-12h-7l1-8Z" />,
    paint: <><path d="m14 4 6 6L10 20H4v-6Z" /><path d="m12 6 6 6" /></>,
    key: <><circle cx="8" cy="15" r="4" /><path d="m11 12 9-9M15 8l3 3M17 6l3 3" /></>,
    snow: <><path d="M12 2v20M4 7l16 10M4 17 20 7M8 4l4 3 4-3M8 20l4-3 4 3" /></>,
    alert: <><path d="M10.3 3.6 2.4 18a2 2 0 0 0 1.8 3h15.6a2 2 0 0 0 1.8-3L13.7 3.6a2 2 0 0 0-3.4 0Z" /><path d="M12 9v4M12 17h.01" /></>,
    eye: <><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z" /><circle cx="12" cy="12" r="2.5" /></>,
    mail: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" /></>,
    phone: <><path d="M7 3H5a2 2 0 0 0-2 2c0 8.8 7.2 16 16 16a2 2 0 0 0 2-2v-2l-4.5-1.5-1 2.3a15 15 0 0 1-9.3-9.3l2.3-1Z" /></>,
    lock: <><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></>,
    swap: <><path d="m7 7 3-3m-3 3 3 3M17 17l-3 3m3-3-3-3M9 4h6a2 2 0 0 1 2 2v5M15 20H9a2 2 0 0 1-2-2v-5" /></>,
    sliders: <><path d="M4 6h10M18 6h2M4 12h3M11 12h9M4 18h10M18 18h2" /><circle cx="16" cy="6" r="2" /><circle cx="9" cy="12" r="2" /><circle cx="16" cy="18" r="2" /></>,
  };
  return <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>;
}

function Button({ children, onClick, kind = "primary", icon }: { children: ReactNode; onClick?: () => void; kind?: "primary" | "secondary" | "ghost"; icon?: IconName }) {
  return <button className={`btn btn-${kind}`} onClick={onClick}>{icon && <Icon name={icon} size={19} />}{children}</button>;
}

function Header({ title, back, right }: { title: string; back?: () => void; right?: ReactNode }) {
  return <div className="page-header">{back ? <button className="icon-btn" onClick={back} aria-label="Retour"><Icon name="arrow" /></button> : <div className="logo-small"><span>S</span></div>}<div className="header-title">{title}</div>{right || <div className="header-spacer" />}</div>;
}

function Field({ icon, label, value, placeholder }: { icon?: IconName; label?: string; value?: string; placeholder?: string }) {
  return <label className="field-wrap">{label && <span>{label}</span>}<div className="field">{icon && <Icon name={icon} size={19} />}<input defaultValue={value} placeholder={placeholder} /></div></label>;
}

function BottomNav({ screen, go }: { screen: Screen; go: (s: Screen) => void }) {
  const items: { label: string; icon: IconName; target: Screen; active: Screen[] }[] = [
    { label: "Accueil", icon: "home", target: "home", active: ["home"] },
    { label: "Logements", icon: "building", target: "housing", active: ["housing", "add-property", "edit-property", "housing-history", "property", "visit"] },
    { label: "Covoiturage", icon: "car", target: "rides", active: ["rides", "ride", "request-detail", "ride-author", "ride-rating", "ride-notifications", "publish", "publish-request", "ride-filters", "my-rides"] },
    { label: "Services", icon: "tools", target: "services", active: ["services", "intervention", "directory", "service-requests", "service-request-detail", "service-review", "service-notifications", "pro", "complaint", "tracking", "complaint-detail"] },
    { label: "Profil", icon: "user", target: "profile", active: ["profile", "activity"] },
  ];
  return <nav className="bottom-nav">{items.map((item) => <button key={item.label} onClick={() => go(item.target)} className={item.active.includes(screen) ? "active" : ""}><Icon name={item.icon} size={21} /><span>{item.label}</span></button>)}</nav>;
}

function StatusBar() {
  return <div className="status-bar"><b>9:41</b><div className="status-icons"><span>●●●</span><span>◔</span><span className="battery" /></div></div>;
}

const properties = [
  { title: "Appartement lumineux S+2", place: "El Manar 2, Tunis", price: "1 150", area: 82, beds: 2, image: photos.apartment },
  { title: "Studio meublé moderne", place: "Ariana Ville", price: "720", area: 42, beds: 1, image: photos.studio },
  { title: "Colocation proche campus", place: "La Marsa, Tunis", price: "560", area: 110, beds: 3, image: photos.marsa },
];

function PropertyCard({ property, onClick, horizontal = false }: { property: typeof properties[number]; onClick: () => void; horizontal?: boolean }) {
  return <button className={`property-card ${horizontal ? "horizontal" : ""}`} onClick={onClick}>
    <div className="property-image"><img src={property.image} alt={property.title} /><span className="favorite"><Icon name="heart" size={18} /></span><span className="photo-count">1/6</span></div>
    <div className="property-info"><div className="property-price">{property.price} TND <small>/ mois</small></div><div className="property-title">{property.title}</div><div className="muted row"><Icon name="map" size={15} />{property.place}</div><div className="specs"><span><Icon name="area" size={15} />{property.area} m²</span><span><Icon name="bed" size={15} />{property.beds} ch.</span></div></div>
  </button>;
}

function SectionTitle({ children, action, onClick }: { children: ReactNode; action?: string; onClick?: () => void }) {
  return <div className="section-title"><strong>{children}</strong>{action && <button onClick={onClick}>{action}</button>}</div>;
}

function Welcome({ go }: { go: (s: Screen) => void }) {
  return <div className="welcome">
    <div className="welcome-orb orb-one" /><div className="welcome-orb orb-two" />
    <div className="brand"><div className="brand-mark"><Icon name="home" size={26} /><Icon name="car" size={21} /></div><span>Student<span>Hub</span></span></div>
    <div className="hero-illustration"><div className="sun" /><div className="cloud cloud-a" /><div className="cloud cloud-b" /><div className="hero-house"><div className="roof" /><div className="door" /><div className="window" /></div><div className="hero-road" /><div className="hero-car"><span /><i /><i /></div><div className="tree"><span /><i /></div></div>
    <div className="welcome-copy"><h1>Tout ce qu'il vous faut,<br /><span>au même endroit.</span></h1><p>Votre logement, vos trajets, simplifiés.</p></div>
    <div className="welcome-actions"><Button onClick={() => go("login")}>Se connecter</Button><Button kind="secondary" onClick={() => go("register")}>Créer un compte</Button><small>En continuant, vous acceptez nos conditions d'utilisation.</small></div>
  </div>;
}

function AuthBrand() {
  return <div className="auth-brand"><div className="brand-mark"><Icon name="home" size={22} /><Icon name="car" size={18} /></div><span>Student<span>Hub</span></span></div>;
}

function AuthIllustration() {
  return <div className="auth-illustration"><span className="auth-sun" /><div className="auth-house"><i /><b /></div><div className="auth-car"><i /><i /></div><span className="auth-road" /></div>;
}

function AuthField({ label, icon, placeholder, type = "text", value, onChange, error, reveal, onReveal }: { label: string; icon: IconName; placeholder: string; type?: string; value: string; onChange: (value: string) => void; error?: string; reveal?: boolean; onReveal?: () => void }) {
  return <label className={`auth-field ${error ? "has-error" : ""}`}><span>{label}</span><div><Icon name={icon} size={18} /><input type={type === "password" && reveal ? "text" : type} value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} />{type === "password" && <button type="button" onClick={onReveal} aria-label={reveal ? "Masquer le mot de passe" : "Afficher le mot de passe"}><Icon name="eye" size={18} /></button>}</div>{error && <small><Icon name="alert" size={12} />{error}</small>}</label>;
}

function Login({ go }: { go: (s: Screen) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const emailError = submitted && (!email ? "L'adresse e-mail est requise." : !email.includes("@") ? "Saisissez une adresse e-mail valide." : "");
  const passwordError = submitted && password.length < 8 ? "Le mot de passe doit contenir au moins 8 caractères." : "";
  const submit = () => { setSubmitted(true); if (email.includes("@") && password.length >= 8) go("home"); };
  return <div className="auth-page">
    <button className="auth-back" onClick={() => go("welcome")}><Icon name="arrow" /></button>
    <AuthBrand /><AuthIllustration />
    <div className="auth-heading"><h1>Bon retour !</h1><p>Connectez-vous pour retrouver vos services.</p></div>
    <div className="auth-form">
      <AuthField label="Adresse e-mail" icon="mail" placeholder="exemple@email.com" value={email} onChange={setEmail} error={emailError || undefined} />
      <AuthField label="Mot de passe" icon="lock" placeholder="Votre mot de passe" type="password" value={password} onChange={setPassword} error={passwordError || undefined} reveal={showPassword} onReveal={() => setShowPassword(!showPassword)} />
      <button className="forgot-link">Mot de passe oublié ?</button>
      <Button onClick={submit}>Se connecter</Button>
      <div className="auth-divider"><span>ou continuer avec</span></div>
      <button className="google-button"><b>G</b> Continuer avec Google</button>
      <p className="auth-switch">Vous n'avez pas encore de compte ? <button onClick={() => go("register")}>Créer un compte</button></p>
    </div>
  </div>;
}

function Register({ go }: { go: (s: Screen) => void }) {
  const [values, setValues] = useState({ name: "", email: "", phone: "", password: "", confirm: "" });
  const [accountType, setAccountType] = useState("Étudiant");
  const [accepted, setAccepted] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const set = (key: keyof typeof values) => (value: string) => setValues({ ...values, [key]: value });
  const error = (key: keyof typeof values) => {
    if (!submitted) return undefined;
    if (!values[key]) return "Ce champ est requis.";
    if (key === "email" && !values.email.includes("@")) return "Saisissez une adresse e-mail valide.";
    if (key === "password" && values.password.length < 8) return "Utilisez au moins 8 caractères.";
    if (key === "confirm" && values.confirm !== values.password) return "Les mots de passe ne correspondent pas.";
    return undefined;
  };
  const submit = () => {
    setSubmitted(true);
    if (Object.values(values).every(Boolean) && values.email.includes("@") && values.password.length >= 8 && values.password === values.confirm && accepted) go("home");
  };
  return <div className="auth-page register-page">
    <button className="auth-back" onClick={() => go("login")}><Icon name="arrow" /></button><AuthBrand />
    <div className="register-intro"><div><h1>Rejoignez-nous !</h1><p>Tous vos services du quotidien, au même endroit.</p></div><AuthIllustration /></div>
    <div className="auth-form">
      <AuthField label="Nom complet" icon="user" placeholder="Votre nom et prénom" value={values.name} onChange={set("name")} error={error("name")} />
      <AuthField label="Adresse e-mail" icon="mail" placeholder="exemple@email.com" value={values.email} onChange={set("email")} error={error("email")} />
      <AuthField label="Numéro de téléphone" icon="phone" placeholder="+216 00 000 000" value={values.phone} onChange={set("phone")} error={error("phone")} />
      <AuthField label="Créer un mot de passe" icon="lock" placeholder="8 caractères minimum" type="password" value={values.password} onChange={set("password")} error={error("password")} reveal={showPassword} onReveal={() => setShowPassword(!showPassword)} />
      <AuthField label="Confirmer le mot de passe" icon="lock" placeholder="Répétez votre mot de passe" type="password" value={values.confirm} onChange={set("confirm")} error={error("confirm")} reveal={showPassword} onReveal={() => setShowPassword(!showPassword)} />
      <label className="account-types"><span>Je suis</span><div>{["Étudiant", "Propriétaire / Locataire", "Prestataire de services"].map((type, index) => <button type="button" key={type} className={accountType === type ? "selected" : ""} onClick={() => setAccountType(type)}><Icon name={(["user", "building", "tools"] as IconName[])[index]} size={18} />{type}</button>)}</div></label>
      <label className={`terms ${submitted && !accepted ? "has-error" : ""}`}><input type="checkbox" checked={accepted} onChange={() => setAccepted(!accepted)} /><span><i><Icon name="check" size={12} /></i>J'accepte les <b>conditions d'utilisation</b> et la <b>politique de confidentialité</b>.</span></label>
      {submitted && !accepted && <div className="terms-error"><Icon name="alert" size={12} />Vous devez accepter les conditions.</div>}
      <Button onClick={submit}>Créer mon compte</Button>
      <p className="auth-switch">Vous avez déjà un compte ? <button onClick={() => go("login")}>Se connecter</button></p>
    </div>
  </div>;
}

function Home({ go }: { go: (s: Screen) => void }) {
  const features: { title: string; text: string; icon: IconName; screen: Screen; className: string }[] = [
    { title: "Trouver un logement", text: "Louez en toute confiance", icon: "building", screen: "housing", className: "blue" },
    { title: "Partager un trajet", text: "Voyagez à petit prix", icon: "car", screen: "rides", className: "mint" },
    { title: "Signaler un problème", text: "Nous vous accompagnons", icon: "alert", screen: "complaint", className: "amber" },
    { title: "Trouver un artisan", text: "Des pros près de chez vous", icon: "tools", screen: "services", className: "purple" },
  ];
  return <div className="page">
    <div className="home-top"><div><span className="eyebrow">BONJOUR</span><h1>Bonjour, Islem !</h1><p>De quoi avez-vous besoin aujourd'hui ?</p></div><div className="top-actions"><button className="icon-btn notification" onClick={() => go("notifications")}><Icon name="bell" /><i /></button><button className="avatar" onClick={() => go("profile")}>IB</button></div></div>
    <div className="content">
      <div className="feature-grid">{features.map((f) => <button className={`feature-card ${f.className}`} onClick={() => go(f.screen)} key={f.title}><span className="feature-icon"><Icon name={f.icon} /></span><strong>{f.title}</strong><small>{f.text}</small><span className="round-arrow"><Icon name="chevron" size={15} /></span></button>)}</div>
      <SectionTitle action="Voir tout" onClick={() => go("housing")}>Logements à découvrir</SectionTitle>
      <div className="horizontal-scroll">{properties.slice(0, 2).map((p) => <PropertyCard key={p.title} property={p} onClick={() => go("property")} />)}</div>
      <SectionTitle action="Voir tout" onClick={() => go("rides")}>Trajets près de vous</SectionTitle>
      <RideMini onClick={() => go("ride")} />
    </div>
  </div>;
}

function Housing({ go }: { go: (s: Screen) => void }) {
  return <div className="page">
    <Header title="Trouver un logement" right={<button className="icon-btn" onClick={() => go("add-property")}><Icon name="plus" /></button>} />
    <div className="content">
      <div className="housing-manage"><button onClick={() => go("add-property")}><span><Icon name="plus" /></span><div><strong>Ajouter un logement</strong><small>Publier une nouvelle annonce</small></div></button><button onClick={() => go("housing-history")}><span><Icon name="clock" /></span><div><strong>Mes annonces</strong><small>Historique et modifications</small></div></button></div>
      <div className="search-field"><Icon name="search" /><input placeholder="Ville, quartier, type de logement..." /><button>⌁</button></div>
      <div className="chips"><button className="selected">Tous</button><button>Studio</button><button>Appartement</button><button>Colocation</button></div>
      <div className="filter-row"><button>Budget <Icon name="chevron" size={13} /></button><button>Pièces <Icon name="chevron" size={13} /></button><button>Meublé <Icon name="chevron" size={13} /></button><button className="filter-count">Filtres <span>2</span></button></div>
      <div className="result-heading"><div><strong>42 logements</strong><small>à Tunis et alentours</small></div><button>Recommandés⌄</button></div>
      <div className="property-list">{properties.map((p) => <PropertyCard horizontal key={p.title} property={p} onClick={() => go("property")} />)}</div>
    </div>
  </div>;
}

function Property({ go }: { go: (s: Screen) => void }) {
  return <div className="page detail-page">
    <div className="gallery"><img src={photos.apartment} alt="Salon lumineux de l'appartement" /><button className="gallery-back" onClick={() => go("housing")}><Icon name="arrow" /></button><button className="gallery-heart"><Icon name="heart" /></button><span>1 / 6</span></div>
    <div className="detail-content">
      <div className="price-line"><div><h1>Appartement lumineux S+2</h1><p><Icon name="map" size={16} /> El Manar 2, Tunis</p></div><strong>1 150 <small>TND/mois</small></strong></div>
      <div className="quick-specs"><div><Icon name="area" /><strong>82 m²</strong><small>Surface</small></div><div><Icon name="bed" /><strong>2</strong><small>Chambres</small></div><div><Icon name="building" /><strong>3e</strong><small>Étage</small></div></div>
      <div className="owner"><div className="avatar photo">MK</div><div><strong>Mehdi Kallel</strong><small>Propriétaire vérifié · Répond en 1h</small></div><button><Icon name="message" size={19} /></button></div>
      <SectionTitle>Description</SectionTitle><p className="description">Bel appartement calme et lumineux, idéalement situé à 5 minutes du campus. Entièrement rénové et prêt à emménager.</p>
      <SectionTitle>Équipements</SectionTitle><div className="amenities"><span>✓ Meublé</span><span>✓ Climatisation</span><span>✓ Wi-Fi inclus</span><span>✓ Balcon</span></div>
      <div className="availability"><Icon name="calendar" /><div><strong>Disponible dès maintenant</strong><small>Bail minimum de 10 mois · Caution : 1 mois</small></div></div>
    </div>
    <div className="sticky-actions"><Button kind="secondary">Contacter</Button><Button onClick={() => go("visit")}>Demander une visite</Button></div>
  </div>;
}

function Visit({ go }: { go: (s: Screen) => void }) {
  const [confirmed, setConfirmed] = useState(false);
  return <div className="page"><Header title={confirmed ? "Demande envoyée" : "Planifier une visite"} back={() => go("property")} />
    <div className="content">
      {confirmed ? <SuccessState icon="calendar" title="Votre visite est demandée !" text="Le propriétaire confirmera votre rendez-vous sous peu." action="Voir mes visites" onClick={() => go("activity")} /> : <>
        <div className="property-summary"><img src={photos.apartment} alt="" /><div><strong>Appartement lumineux S+2</strong><span><Icon name="map" size={14} /> El Manar 2</span><b>1 150 TND/mois</b></div></div>
        <SectionTitle>Choisissez une date</SectionTitle>
        <div className="calendar-card"><div className="calendar-head"><button>‹</button><strong>Juin 2025</strong><button>›</button></div><div className="weekdays">{["L","M","M","J","V","S","D"].map((d,i)=><span key={i}>{d}</span>)}</div><div className="days">{Array.from({length:35},(_,i)=><button key={i} className={i===18 ? "active" : i<5 || i>30 ? "disabled" : ""}>{i<5 ? 27+i : i-4}</button>)}</div></div>
        <SectionTitle>Créneaux disponibles</SectionTitle><div className="time-slots"><button>09:30</button><button className="selected">11:00</button><button>14:30</button><button>16:00</button></div>
        <div className="info-note"><Icon name="check" /><span>Visite sélectionnée : <strong>jeudi 19 juin à 11:00</strong></span></div>
        <Button onClick={() => setConfirmed(true)}>Confirmer la demande</Button>
      </>}
    </div>
  </div>;
}

function PropertyForm({ go, edit = false }: { go: (s: Screen) => void; edit?: boolean }) {
  const [photosList, setPhotosList] = useState(edit ? [photos.apartment, photos.studio, photos.marsa] : [photos.apartment, photos.studio]);
  const [equipment, setEquipment] = useState(["Meublé", "Wi-Fi", "Climatisation"]);
  const [submitted, setSubmitted] = useState(false);
  const toggleEquipment = (item: string) => setEquipment(equipment.includes(item) ? equipment.filter(value => value !== item) : [...equipment, item]);
  return <div className="page"><Header title={edit ? "Modifier le logement" : "Ajouter un logement"} back={() => go(edit ? "housing-history" : "housing")} /><div className="content listing-form">
    <div className="form-section-title"><span>1</span><div><strong>Titre et description</strong><small>Présentez votre logement</small></div></div>
    <Field label="Titre de l'annonce *" value={edit ? "Appartement lumineux S+2" : ""} placeholder="Ex. Studio meublé proche campus" icon="building" />
    <label className="field-wrap"><span>Description *</span><textarea defaultValue={edit ? "Bel appartement calme et lumineux, idéalement situé à 5 minutes du campus." : ""} placeholder="Décrivez le logement, son environnement et ses points forts..." /></label>
    <div className="form-section-title"><span>2</span><div><strong>Prix et location</strong><small>Définissez les conditions</small></div></div>
    <div className="split"><Field label="Loyer mensuel (TND) *" value={edit ? "1 150" : ""} placeholder="Ex. 850" /><label className="field-wrap"><span>Type de location *</span><div className="select-field"><div><b>{edit ? "Location entière" : "Choisir"}</b><small>Mensuelle</small></div><Icon name="chevron" /></div></label></div>
    <div className="form-section-title"><span>3</span><div><strong>Caractéristiques</strong><small>Informations principales</small></div></div>
    <div className="triple-fields"><Field label="Surface (m²) *" value={edit ? "82" : ""} placeholder="m²" /><Field label="Chambres *" value={edit ? "2" : ""} placeholder="0" /><Field label="Étage" value={edit ? "3" : ""} placeholder="0" /></div>
    <div className="form-section-title"><span>4</span><div><strong>Localisation</strong><small>Où se trouve le logement ?</small></div></div>
    <div className="split"><Field label="Ville *" value={edit ? "Tunis" : ""} placeholder="Ville" icon="map" /><Field label="Quartier *" value={edit ? "El Manar 2" : ""} placeholder="Quartier" /></div><Field label="Adresse complète *" value={edit ? "12 rue des Jasmins" : ""} placeholder="Rue, numéro, résidence..." icon="map" />
    <div className="form-section-title"><span>5</span><div><strong>Photos</strong><small>Ajoutez jusqu'à 8 photos</small></div></div>
    <div className="photo-manager">{photosList.map((photo,index) => <div key={`${photo}-${index}`}><img src={photo} alt={`Aperçu ${index + 1}`} />{index === 0 && <span>Principale</span>}<button onClick={() => setPhotosList(photosList.filter((_,photoIndex) => photoIndex !== index))}>×</button></div>)}<button className="add-photo" onClick={() => setPhotosList([...photosList, photos.marsa])}><Icon name="camera" /><strong>Ajouter</strong><small>JPG ou PNG</small></button></div>
    <div className="form-section-title"><span>6</span><div><strong>Équipements</strong><small>Sélectionnez les éléments disponibles</small></div></div>
    <div className="equipment-grid">{["Meublé","Wi-Fi","Climatisation","Chauffage","Parking","Ascenseur"].map(item => <button className={equipment.includes(item) ? "selected" : ""} onClick={() => toggleEquipment(item)} key={item}><Icon name={equipment.includes(item) ? "check" : "plus"} size={15} />{item}</button>)}</div>
    {edit && <label className="field-wrap"><span>Disponibilité</span><div className="availability-switch"><div><strong>Annonce disponible</strong><small>Visible dans les résultats de recherche</small></div><button className="active"><i /></button></div></label>}
    {submitted && <div className="inline-form-error"><Icon name="alert" size={14} />Complétez les champs obligatoires indiqués par un astérisque.</div>}
    <div className="form-actions"><Button kind="secondary" onClick={() => go(edit ? "housing-history" : "housing")}>Annuler</Button><Button onClick={() => submitted ? go("housing-history") : setSubmitted(true)}>{edit ? "Enregistrer les modifications" : "Publier le logement"}</Button></div>
  </div></div>;
}

function HousingHistory({ go }: { go: (s: Screen) => void }) {
  const listings = [
    { title: "Appartement lumineux S+2", price: "1 150", place: "El Manar 2, Tunis", status: "Loué", image: photos.apartment, dates: "Publié le 04 mars · Modifié le 12 juin" },
    { title: "Studio meublé moderne", price: "720", place: "Ariana Ville", status: "Retiré", image: photos.studio, dates: "Publié le 18 janvier · Modifié le 02 mai" },
    { title: "Colocation proche campus", price: "560", place: "La Marsa, Tunis", status: "Expiré", image: photos.marsa, dates: "Publié le 10 septembre · Expiré le 10 juin" },
  ];
  return <div className="page"><Header title="Historique des logements" back={() => go("housing")} right={<button className="icon-btn" onClick={() => go("add-property")}><Icon name="plus" /></button>} /><div className="content"><div className="history-summary"><Icon name="building" /><div><strong>3 annonces publiées</strong><small>Retrouvez et gérez vos anciens logements.</small></div></div>{listings.map((listing,index) => <div className="listing-history-card" key={listing.title}><img src={listing.image} alt={listing.title} /><div className="listing-history-main"><div><span className={`listing-status ${listing.status.toLowerCase()}`}>{listing.status}</span><strong>{listing.title}</strong><small><Icon name="map" size={13} />{listing.place}</small><b>{listing.price} TND/mois</b><em>{listing.dates}</em></div><div className="listing-actions"><button onClick={() => go("property")}>Consulter les détails</button>{index === 0 ? <button onClick={() => go("edit-property")}>Modifier</button> : <button onClick={() => go("edit-property")}>Republier l'annonce</button>}</div></div></div>)}<div className="history-empty housing-empty"><Icon name="building" size={25} /><strong>Aucune autre annonce</strong><small>Vos futures publications apparaîtront dans cet historique.</small></div></div></div>;
}

function RideMini({ onClick }: { onClick: () => void }) {
  return <button className="ride-mini" onClick={onClick}><div className="route-time"><strong>08:00</strong><span><i /><b /><i /></span><strong>10:10</strong></div><div className="route-places"><span>Tunis · Exemple</span><span>Sousse · Exemple</span></div><div className="ride-footer"><div className="driver"><span className="avatar small">WA</span><span>Walid · Exemple <b>★ 4,9 · Exemple</b></span></div><strong>18 TND · Exemple</strong></div></button>;
}

function Rides({ go }: { go: (s: Screen) => void }) {
  const [searched, setSearched] = useState(false);
  const [tab, setTab] = useState("Offres");
  const [zoneOpen, setZoneOpen] = useState(false);
  const [zone, setZone] = useState("Ariana");
  return <div className="page rides-page"><div className="rides-header"><div><span>COVOITURAGE</span><h1>Partagez vos trajets,<br />simplement.</h1></div><button className="icon-btn notification" onClick={() => go("ride-notifications")}><Icon name="bell" /><i /></button></div>
    <div className="content rides-content">
      <div className="zone-selector"><div><Icon name="map" size={16} /><span>Votre zone : <strong>{zone}</strong></span></div><button onClick={() => setZoneOpen(!zoneOpen)}>Changer <Icon name="chevron" size={13} /></button>{zoneOpen && <div className="zone-menu">{["Ariana","Tunis Centre","El Manar","La Marsa","Sousse","Sfax","Nabeul"].map(item => <button key={item} onClick={() => { setZone(item); setZoneOpen(false); }} className={zone === item ? "selected" : ""}>{item}{zone === item && <Icon name="check" size={14} />}</button>)}</div>}</div>
      <div className="ride-search-card enhanced"><div className="map-pattern"><i /><i /><i /></div><div className="trip-fields enhanced"><span className="trip-line"><i /><b /><i /></span><div><Field value="Tunis" icon="map" /><Field value="Sousse" icon="map" /></div><button className="swap-button"><Icon name="swap" size={19} /></button></div><div className="ride-options"><button><Icon name="calendar" size={18} /><span><small>Date</small>19 juin</span></button><button><Icon name="users" size={18} /><span><small>Voyageurs</small>1 passager</span></button></div><Button icon="search" onClick={() => setSearched(true)}>Rechercher un trajet</Button></div>
      <div className="ride-main-tabs">{["Offres","Demandes","Mes trajets"].map(item => <button key={item} className={tab === item ? "active" : ""} onClick={() => item === "Mes trajets" ? go("my-rides") : setTab(item)}>{item}</button>)}</div>
      <div className="ride-quick-actions"><button onClick={() => go("publish")}><span className="quick-art find"><Icon name="car" /><i /></span><div><strong>Proposer un trajet</strong><small>Partagez votre voiture.</small></div><Icon name="chevron" size={17} /></button><button onClick={() => go("publish-request")}><span className="quick-art offer"><Icon name="map" /><i /></span><div><strong>Publier une demande</strong><small>Dites où vous allez.</small></div><Icon name="chevron" size={17} /></button></div>
      <div className="ride-tools"><div><button className="filter-button" onClick={() => go("ride-filters")}><Icon name="sliders" size={17} /> Filtres <b>2</b></button><span className="filter-chip">Zone : {zone} ×</span><span className="filter-chip">19 juin ×</span></div></div>
      <SectionTitle action="Voir tout" onClick={() => setSearched(true)}>Trajets disponibles</SectionTitle><p className="result-sub">{searched ? "Résultats · Toutes les données sont des exemples" : `${tab} suggérées · Données d'exemple`}</p>
      <div className="rides-list">{tab === "Offres" ? <><RideCard from="Tunis" to="Sousse" times={["08:00","10:10"]} date="Jeu. 19 juin" name="Walid Amri" price="18" seats={3} status="Ouvert" onClick={() => go("ride")} /><RideCard from="Ariana" to="Tunis" times={["08:30","09:05"]} date="Jeu. 19 juin" name="Sarra Mansour" price="6" seats={0} status="Complet" onClick={() => go("ride")} /><RideCard from="Tunis" to="Nabeul" times={["15:00","16:15"]} date="Ven. 20 juin" name="Islem Ben Salah" price="12" seats={2} status="Ouvert" own onClick={() => go("ride-author")} /></> : <><DemandCard from="Ariana" to="Tunis" time="07:45" date="Jeu. 19 juin" name="Yasmine Gharbi" seats={1} zone={zone} onClick={() => go("request-detail")} /><DemandCard from="Sfax" to="Sousse" time="17:30" date="Sam. 21 juin" name="Hatem Jaziri" seats={2} zone="Sfax" onClick={() => go("request-detail")} /><DemandCard from="Tunis" to="Nabeul" time="15:00" date="Ven. 20 juin" name="Islem Ben Salah" seats={1} zone="Tunis" own onClick={() => go("ride-author")} /></>}</div>
    </div>
  </div>;
}

function RideCard({ from, to, times, date = "Jeu. 19 juin", name, price, seats, status = "Ouvert", own = false, note, onClick }: { from: string; to: string; times: string[]; date?: string; name: string; price: string; seats: number; status?: string; own?: boolean; note?: string; onClick: () => void }) {
  return <article className="ride-card detailed offer-card"><div className="post-type-row"><span className="post-type offer">Offre</span><span className={`status ${status === "Complet" ? "finished" : "solved"}`}>{status}</span></div><div className="ride-driver-row"><div className="driver"><span className="avatar small">{name.split(" ").map(part => part[0]).join("").slice(0,2)}</span><span><strong>{name} <em>Exemple</em></strong><b>★ 4,9 · Note d'exemple</b></span></div><div className="ride-price"><strong>{price} TND</strong><small>prix d'exemple / pers.</small></div></div><div className="ride-card-top"><div className="route-vertical"><span><i /><b /><i /></span><div><p><strong>{times[0]}</strong> {from}</p><small>Trajet d'exemple</small><p><strong>{times[1]}</strong> {to}</p></div></div></div><div className="ride-meta"><span><Icon name="calendar" size={14} />{date}</span><span><Icon name="users" size={14} />{seats} places restantes</span></div>{note && <div className="ride-comfort">{note}</div>}<div className="ride-card-bottom"><small>Données fictives</small>{own ? <span className="own-label">Votre annonce</span> : <button disabled={status === "Complet"} onClick={onClick}>{status === "Complet" ? "Complet" : "Réserver"} <Icon name="chevron" size={14} /></button>}</div></article>;
}

function DemandCard({ from, to, time, date, name, seats, zone, own = false, onClick }: { from: string; to: string; time: string; date: string; name: string; seats: number; zone: string; own?: boolean; onClick: () => void }) {
  return <article className="ride-card detailed demand-card"><div className="post-type-row"><span className="post-type demand">Demande</span><span className="status progress">Cherche un trajet</span></div><div className="ride-driver-row"><div className="driver"><span className="avatar small teal">{name.split(" ").map(part => part[0]).join("").slice(0,2)}</span><span><strong>{name} <em>Exemple</em></strong><b>Passager · Profil vérifié</b></span></div><div className="need-seats"><Icon name="users" size={15} /><strong>{seats}</strong><small>place{seats > 1 ? "s" : ""}</small></div></div><div className="demand-route"><span><i /><b /><i /></span><div><strong>{from}</strong><Icon name="chevron" size={15} /><strong>{to}</strong></div></div><div className="ride-meta"><span><Icon name="calendar" size={14} />{date} · {time}</span><span><Icon name="map" size={14} />Zone : {zone}</span></div><div className="ride-card-bottom"><small>Données fictives</small>{own ? <span className="own-label">Votre annonce</span> : <button onClick={onClick}>Je peux l'emmener <Icon name="chevron" size={14} /></button>}</div></article>;
}

function RideDetail({ go }: { go: (s: Screen) => void }) {
  const [booked, setBooked] = useState(false);
  const [seats, setSeats] = useState(1);
  return <div className="page"><Header title="Détails du trajet" back={() => go("rides")} />
    <div className="content">{booked ? <div className="ride-requested"><SuccessState icon="car" title="Réservation envoyée !" text="Le conducteur a reçu votre demande de réservation." action="Gérer mes réservations" onClick={() => go("my-rides")} /><span className="request-status"><i /> En attente de confirmation</span></div> : <>
      <div className="detail-type"><span className="post-type offer">Offre</span><span>Données entièrement fictives</span></div><div className="ride-detail-hero enhanced-detail"><span>JEUDI 19 JUIN · TRAJET D'EXEMPLE</span><div className="detail-map-line"><i /><b /><Icon name="car" size={22} /><b /><i /></div><div className="detail-stops"><div><strong>08:00</strong><span>Place Pasteur</span><small>Tunis</small></div><div><strong>10:10</strong><span>Gare centrale</span><small>Sousse</small></div></div><div className="detail-price-row"><span>2h 10 · Direct</span><strong>18 TND <small>prix d'exemple / place</small></strong></div></div>
      <div className="driver-profile"><span className="avatar large">WA</span><div><strong>Walid Amri <em>Exemple</em> <i className="verified-check"><Icon name="check" size={11} /></i></strong><span><b>★ 4,9</b> · Note d'exemple</span><small>Profil d'exemple vérifié</small></div></div>
      <div className="ride-highlights"><span><Icon name="users" />3 places restantes</span><span><Icon name="car" />Peugeot 208</span><span><Icon name="building" />1 bagage cabine</span></div>
      <SectionTitle>Itinéraire</SectionTitle><div className="route-addresses"><div><i /><span><strong>Point de rendez-vous</strong><small>Devant la station de métro, Place Pasteur</small></span></div><div><i /><span><strong>Destination</strong><small>Entrée principale de la gare de Sousse</small></span></div></div>
      <SectionTitle>Commentaire du conducteur</SectionTitle><div className="driver-message">« Départ à l'heure. Je peux faire un petit détour dans le centre de Sousse. »</div>
      <div className="preference-list"><span>Climatisation</span><span>Non-fumeur</span><span>Petit bagage</span></div>
      <SectionTitle>Nombre de places</SectionTitle><div className="detail-seat-stepper"><button onClick={() => setSeats(Math.max(1, seats - 1))}>−</button><span><strong>{seats}</strong> / 3 disponibles</span><button onClick={() => setSeats(Math.min(3, seats + 1))}>+</button></div>
      <div className="booking-total"><span>{seats} place{seats > 1 ? "s" : ""}</span><strong>{seats * 18} TND <small>exemple</small></strong></div><Button onClick={() => setBooked(true)}>Réserver des places</Button>
    </>}</div>
  </div>;
}

function DemandDetail({ go }: { go: (s: Screen) => void }) {
  const [sent, setSent] = useState(false);
  return <div className="page"><Header title="Détails de la demande" back={() => go("rides")} /><div className="content">{sent ? <div className="ride-requested"><SuccessState icon="car" title="Proposition envoyée !" text="La passagère doit maintenant confirmer votre proposition." action="Voir mes propositions" onClick={() => go("my-rides")} /><span className="request-status"><i /> En attente de confirmation</span></div> : <>
    <div className="detail-type"><span className="post-type demand">Demande</span><span>Données entièrement fictives</span></div>
    <div className="demand-detail-hero"><div className="avatar large teal">YG</div><div><span>CHERCHE UN TRAJET</span><h1>Yasmine Gharbi <em>Exemple</em></h1><p>Profil d'exemple vérifié</p></div></div>
    <div className="ride-detail-hero enhanced-detail demand-theme"><span>JEUDI 19 JUIN · DEMANDE D'EXEMPLE</span><div className="detail-map-line"><i /><b /><Icon name="users" size={22} /><b /><i /></div><div className="detail-stops"><div><strong>07:45</strong><span>Ariana Centre</span><small>Départ souhaité</small></div><div><strong>08:30</strong><span>Tunis Centre</span><small>Arrivée souhaitée</small></div></div></div>
    <div className="ride-highlights"><span><Icon name="users" />1 place nécessaire</span><span><Icon name="calendar" />Jeu. 19 juin</span><span><Icon name="map" />Zone Ariana</span></div>
    <SectionTitle>Commentaire de la passagère</SectionTitle><div className="driver-message demand-comment">« Je dois arriver avant 8h45 près de l'avenue Habib-Bourguiba. Petit sac uniquement. »</div>
    <div className="info-note"><Icon name="bell" /><span>En proposant ce trajet, Yasmine recevra une notification dans l'application.</span></div>
    <Button onClick={() => setSent(true)}>Je peux l'emmener</Button>
  </>}</div></div>;
}

function RideAuthor({ go }: { go: (s: Screen) => void }) {
  const [type, setType] = useState<"Offre" | "Demande">("Offre");
  const [confirmed, setConfirmed] = useState(2);
  const [cancelled, setCancelled] = useState(false);
  return <div className="page"><Header title="Gérer mon annonce" back={() => go("my-rides")} /><div className="content">
    <div className="author-switch"><button className={type === "Offre" ? "active" : ""} onClick={() => { setType("Offre"); setConfirmed(2); }}>Offre</button><button className={type === "Demande" ? "active" : ""} onClick={() => { setType("Demande"); setConfirmed(0); }}>Demande</button></div>
    <div className="author-summary"><div><span className={`post-type ${type === "Offre" ? "offer" : "demand"}`}>{type}</span><span className={`status ${confirmed >= 3 ? "finished" : "solved"}`}>{cancelled ? "Annulé" : confirmed >= 3 ? "Complet" : "Ouvert"}</span></div><div className="managed-route"><span><strong>08:00</strong>Tunis</span><i><Icon name="car" size={18} /></i><span><strong>10:10</strong>Sousse</span></div><small>Données d'exemple · Jeudi 19 juin</small></div>
    <div className="confirmed-counter"><div><strong>{type === "Offre" ? `${confirmed}/3` : confirmed ? "1 proposition retenue" : "0 proposition retenue"}</strong><span>{type === "Offre" ? "places confirmées" : "pour votre demande"}</span></div><span className="status progress">{confirmed ? "Mise à jour" : "En attente"}</span></div>
    <SectionTitle>{type === "Offre" ? "Réservations" : "Propositions"}</SectionTitle>
    {type === "Demande" && <div className="info-note"><Icon name="alert" /><span>Confirmer une proposition refusera automatiquement toutes les autres.</span></div>}
    <PersonRequest initials="SM" name="Sarra Mansour" places={type === "Offre" ? "1 place demandée" : "Propose 08:00 · 15 TND"} confirmed={confirmed > 0} onConfirm={() => setConfirmed(type === "Offre" ? Math.min(3, confirmed + 1) : 1)} />
    <PersonRequest initials="AK" name="Ahmed Kacem" places={type === "Offre" ? "1 place demandée" : "Propose 08:15 · 18 TND"} forcedRefused={type === "Demande" && confirmed > 0} onConfirm={() => setConfirmed(type === "Offre" ? Math.min(3, confirmed + 1) : 1)} />
    <button className="cancel-post" onClick={() => setCancelled(true)}><Icon name="alert" size={17} />{cancelled ? "Annonce annulée" : "Annuler l'annonce"}</button>
  </div></div>;
}

function PersonRequest({ initials, name, places, confirmed, forcedRefused = false, onConfirm }: { initials: string; name: string; places: string; confirmed?: boolean; forcedRefused?: boolean; onConfirm: () => void }) {
  const [refused, setRefused] = useState(false);
  return <div className="person-request"><span className="avatar small">{initials}</span><div><strong>{name} <em>Exemple</em></strong><small>{places} · Donnée d'exemple</small></div>{confirmed ? <span className="status solved">Confirmée</span> : refused || forcedRefused ? <span className="status refused">Refusée</span> : <div className="request-actions"><button onClick={onConfirm}><Icon name="check" size={13} />Confirmer</button><button onClick={() => setRefused(true)}>Refuser</button></div>}</div>;
}

function PublishRide({ go, initialType = "Offre" }: { go: (s: Screen) => void; initialType?: "Offre" | "Demande" }) {
  const [success, setSuccess] = useState(false);
  const [type, setType] = useState<"Offre" | "Demande">(initialType);
  const [submitted, setSubmitted] = useState(false);
  const [places, setPlaces] = useState(1);
  return <div className="page"><Header title={success ? "Annonce publiée" : "Publier un trajet"} back={() => go("rides")} /><div className="content">
    {success ? <div className="publish-success"><SuccessState icon="car" title={type === "Offre" ? "Votre offre est en ligne !" : "Votre demande est en ligne !"} text={type === "Offre" ? "Les passagers peuvent maintenant réserver des places." : "Les conducteurs de votre zone peuvent maintenant proposer ce trajet."} action="Voir mes trajets" onClick={() => go("my-rides")} /><div className={`published-summary ${type === "Demande" ? "demand-summary" : ""}`}><span><b>Tunis</b>08:00</span><i><Icon name={type === "Offre" ? "car" : "users"} size={17} /></i><span><b>Sousse</b>10:10</span><strong>{type === "Offre" ? "18 TND · Exemple" : "Demande · Exemple"}</strong></div></div> : <div className="form-stack publish-form">
      <div className="publish-type-switch"><button className={type === "Offre" ? "active" : ""} onClick={() => setType("Offre")}><span className="post-type offer">Offre</span>Je conduis</button><button className={type === "Demande" ? "active" : ""} onClick={() => setType("Demande")}><span className="post-type demand">Demande</span>Je cherche</button></div>
      <div className="form-section-title"><span>1</span><div><strong>Votre itinéraire</strong><small>Où allez-vous ?</small></div></div>
      <Field label="Départ" value="Tunis, Place Pasteur" icon="map" /><Field label="Destination" value="Sousse, Gare centrale" icon="map" />
      <label className="field-wrap"><span>Zone</span><div className="select-field"><div><b>Ariana</b><small>Ville ou secteur choisi, sans GPS</small></div><Icon name="chevron" /></div></label>
      <div className="route-preview"><span><i /><b /><i /></span><div><small>Aperçu décoratif de l'itinéraire</small><strong>Tunis → Sousse · Exemple</strong></div><Icon name="car" /></div>
      <div className="form-section-title"><span>2</span><div><strong>Date et places</strong><small>Organisez votre départ</small></div></div>
      <div className="split"><Field label="Date" value="19 juin 2025" icon="calendar" /><Field label="Heure" value="08:00" icon="clock" /></div>
      <label className="field-wrap"><span>{type === "Offre" ? "Places offertes" : "Places nécessaires"}</span><div className="stepper"><button onClick={() => setPlaces(Math.max(1, places - 1))}>−</button><strong>{places}</strong><button onClick={() => setPlaces(places + 1)}>+</button></div></label>
      {type === "Offre" && <Field label="Participation aux frais (TND)" value="18" />}
      <div className="form-section-title"><span>3</span><div><strong>Détails pratiques</strong><small>Aidez les autres membres à vous comprendre</small></div></div>
      <label className="field-wrap"><span>Commentaire (facultatif)</span><textarea placeholder="Ajoutez des informations utiles..." /></label>
      {submitted && <><div className="inline-form-error"><Icon name="alert" size={14} />Vérifiez les champs obligatoires et les valeurs numériques.</div><div className="field-example-error">Exemple d'erreur : la participation doit être supérieure à 0 TND.</div></>}
      <div className="info-note"><Icon name="check" /><span>{type === "Offre" ? "Prix d'exemple conseillé : 15–20 TND." : "Aucun prix n'est demandé pour une demande de trajet."}</span></div>
      <Button onClick={() => submitted ? setSuccess(true) : setSubmitted(true)}>Publier</Button>
    </div>}
  </div></div>;
}

function RideFilters({ go }: { go: (s: Screen) => void }) {
  const [sort, setSort] = useState("Date la plus proche");
  const [type, setType] = useState("Offres");
  const [zone, setZone] = useState("Ariana");
  const empty = zone === "Sfax" && type === "Demandes";
  return <div className="page filter-overlay"><div className="filter-backdrop" onClick={() => go("rides")} /><div className="filter-sheet"><div className="sheet-handle" /><div className="sheet-title"><div><h1>Filtrer les trajets</h1><p>Les zones sont choisies manuellement, sans GPS.</p></div><button onClick={() => go("rides")}>×</button></div>
    <SectionTitle>Type de publication</SectionTitle><div className="choice-grid">{["Offres","Demandes"].map(item => <button key={item} className={type === item ? "selected" : ""} onClick={() => setType(item)}>{item}</button>)}</div>
    <SectionTitle>Zone</SectionTitle><div className="filter-zone-chips">{["Ariana","Tunis","Sousse","Sfax"].map(item => <button key={item} className={zone === item ? "selected" : ""} onClick={() => setZone(item)}>{item}</button>)}</div>
    <SectionTitle>Date</SectionTitle><div className="filter-date"><Icon name="calendar" size={17} /><span>Jeudi 19 juin 2025</span><Icon name="chevron" size={14} /></div>
    {type === "Offres" && <><SectionTitle>Prix maximum</SectionTitle><div className="price-range"><div><span>0 TND</span><strong>20 TND max. · Exemple</strong><span>50 TND</span></div><input type="range" min="0" max="50" defaultValue="20" /></div></>}
    <SectionTitle>Places disponibles minimum</SectionTitle><div className="passenger-filter"><button>−</button><span><strong>2</strong> places minimum</span><button>+</button></div>
    <SectionTitle>Trier par</SectionTitle><div className="sort-list">{["Date la plus proche","Prix le plus bas"].map(item => <button key={item} onClick={() => setSort(item)} className={sort === item ? "selected" : ""}><span>{item}</span><i><b /></i></button>)}</div>
    {empty && <div className="ride-empty"><span><Icon name="search" size={28} /></span><strong>Aucun trajet trouvé</strong><p>Publiez une demande pour prévenir les conducteurs de cette zone.</p><Button kind="secondary" onClick={() => go("publish-request")}>Publier une demande</Button></div>}
    {!empty && <div className="filter-selected"><span>Offres ×</span><span>Zone : {zone} ×</span><span>19 juin ×</span></div>}
    <div className="filter-apply"><Button onClick={() => go("rides")}>{empty ? "Modifier les filtres" : "Afficher 4 trajets"}</Button></div>
  </div></div>;
}

function MyRides({ go }: { go: (s: Screen) => void }) {
  const [role, setRole] = useState("En tant que conducteur");
  const [cancel, setCancel] = useState<"driver" | "passenger" | null>(null);
  return <div className="page"><Header title="Mes trajets" back={() => go("rides")} right={<button className="icon-btn" onClick={() => go("publish")}><Icon name="plus" /></button>} /><div className="role-switch">{["En tant que conducteur","En tant que passager"].map(item => <button key={item} onClick={() => setRole(item)} className={role === item ? "active" : ""}>{item}</button>)}</div><div className="content">
    {role === "En tant que conducteur" ? <><HistoryItem role="Conducteur" route="Tunis → Sousse" date="19 juin · 08:00" status="Ouvert" action="Gérer" onAction={() => go("ride-author")} onCancel={() => setCancel("driver")} /><HistoryItem role="Conducteur" route="Sfax → Sousse" date="21 juin · 17:30" status="Complet" action="Gérer" onAction={() => go("ride-author")} onCancel={() => setCancel("driver")} /><HistoryItem role="Conducteur" route="Tunis → Nabeul" date="2 juin · 09:00" status="Terminé" action="Noter" onAction={() => go("ride-rating")} past /><HistoryItem role="Conducteur" route="Ariana → Nabeul" date="28 mai · 11:00" status="Annulé" action="Voir" onAction={() => go("ride-author")} past /></> : <><HistoryItem role="Passager · Réservation confirmée" route="Ariana → Tunis" date="19 juin · 08:30" status="Confirmée" action="Voir" onAction={() => go("ride")} onCancel={() => setCancel("passenger")} /><HistoryItem role="Passager · Proposition" route="Tunis → Sousse" date="21 juin · 08:00" status="En attente" action="Voir" onAction={() => go("request-detail")} onCancel={() => setCancel("passenger")} /><HistoryItem role="Passager" route="Tunis → Sfax" date="2 juin · 07:00" status="Terminé" action="Noter" onAction={() => go("ride-rating")} past /><HistoryItem role="Passager" route="La Marsa → Tunis" date="26 mai · 17:00" status="Annulée" action="Voir" onAction={() => go("ride")} past /></>}
    <div className="history-empty"><Icon name="car" size={25} /><strong>Aucun autre trajet</strong><small>Vos prochains trajets apparaîtront ici.</small></div>
  </div>{cancel && <div className="dialog-backdrop"><div className="cancel-dialog"><span><Icon name="alert" /></span><h2>Annuler ce trajet ?</h2><p>{cancel === "driver" ? "Toutes les réservations seront annulées et les participants notifiés." : "Vos places seront libérées pour d'autres passagers."}</p><div><Button kind="secondary" onClick={() => setCancel(null)}>Conserver</Button><button onClick={() => setCancel(null)}>Confirmer l'annulation</button></div></div></div>}</div>;
}

function HistoryItem({ role, route, date, status, action, onAction, onCancel, past = false }: { role: string; route: string; date: string; status: string; action: string; onAction: () => void; onCancel?: () => void; past?: boolean }) {
  const statusClass = status === "Terminé" || status === "Annulé" || status === "Annulée" ? "finished" : status === "En attente" ? "waiting" : status === "Confirmée" || status === "Ouvert" ? "solved" : "progress";
  return <div className="history-item"><div className="history-top"><span className={`status ${statusClass}`}>{status}</span><small>Données d'exemple</small></div><h3>{route}</h3><p><Icon name="calendar" size={14} />{date}</p><p><Icon name="user" size={14} />{role}</p><div className="history-actions"><button className="history-main" onClick={onAction}>{action}</button>{past ? <span>Annulation indisponible après le départ.</span> : <button className="history-cancel" onClick={onCancel}>Annuler</button>}</div></div>;
}

function RideRating({ go }: { go: (s: Screen) => void }) {
  const [rating, setRating] = useState(0);
  const [sent, setSent] = useState(false);
  return <div className="page"><Header title="Noter le trajet" back={() => go("my-rides")} /><div className="content">{sent ? <SuccessState icon="star" title="Merci pour votre avis !" text="Votre note a été enregistrée. Chaque participant ne peut noter qu'une fois ce trajet." action="Retour à mes trajets" onClick={() => go("my-rides")} /> : <div className="rating-screen"><span className="avatar large">WA</span><h1>Comment s'est passé le trajet ?</h1><p>Walid Amri · Nom d'exemple<br />Tunis → Sousse · Trajet terminé</p><div className="rating-stars">{[1,2,3,4,5].map(star => <button key={star} className={rating >= star ? "active" : ""} onClick={() => setRating(star)}><Icon name="star" size={32} /></button>)}</div><strong>{rating ? `${rating} sur 5` : "Choisissez une note"}</strong><label className="field-wrap"><span>Commentaire (facultatif)</span><textarea placeholder="Partagez votre expérience..." /></label><Button onClick={() => rating && setSent(true)}>Envoyer mon avis</Button><small>Disponible uniquement pour les participants confirmés d'un trajet terminé.</small></div>}</div></div>;
}

function RideNotifications({ go }: { go: (s: Screen) => void }) {
  const items = [
    { title: "Nouvelle demande dans votre zone", text: "Yasmine cherche Ariana → Tunis demain.", time: "Il y a 5 min", icon: "map" as IconName, target: "request-detail" as Screen },
    { title: "Nouvelle réservation reçue", text: "Sarra demande 1 place pour Tunis → Sousse.", time: "Il y a 25 min", icon: "users" as IconName, target: "ride-author" as Screen },
    { title: "Proposition confirmée", text: "Votre proposition pour Ariana → Tunis est confirmée.", time: "Il y a 2 h", icon: "check" as IconName, target: "request-detail" as Screen },
    { title: "Réservation refusée", text: "Votre réservation d'exemple n'a pas été retenue.", time: "Hier", icon: "alert" as IconName, target: "my-rides" as Screen },
    { title: "Trajet annulé", text: "Le trajet Tunis → Nabeul a été annulé.", time: "12 juin", icon: "alert" as IconName, target: "my-rides" as Screen },
    { title: "Rappel avant départ", text: "Votre trajet commence demain à 08:00.", time: "11 juin", icon: "clock" as IconName, target: "ride" as Screen },
  ];
  return <div className="page"><Header title="Notifications Covoiturage" back={() => go("rides")} right={<button className="text-button">Tout lire</button>} /><div className="content no-top"><div className="sample-notice">Toutes les personnes et tous les trajets sont fictifs.</div>{items.map((item,index) => <button className={`ride-notification ${index < 3 ? "unread" : ""}`} key={item.title} onClick={() => go(item.target)}><span><Icon name={item.icon} /></span><div><strong>{item.title}</strong><p>{item.text}</p><small>{item.time}</small></div>{index < 3 && <i />}</button>)}</div></div>;
}

const categories: { label: string; icon: IconName; className: string }[] = [
  { label: "Plomberie", icon: "droplet", className: "blue" }, { label: "Électricité", icon: "bolt", className: "amber" }, { label: "Climatisation", icon: "snow", className: "mint" }, { label: "Peinture", icon: "paint", className: "purple" }, { label: "Serrurerie", icon: "key", className: "rose" }, { label: "Autres", icon: "tools", className: "gray" },
];

function Services({ go }: { go: (s: Screen) => void }) {
  return <div className="page"><Header title="Services" right={<button className="icon-btn notification" onClick={() => go("service-notifications")}><Icon name="bell" /><i /></button>} /><div className="content">
    <div className="services-hero"><span>DES PROS DE CONFIANCE</span><h1>Besoin d'un artisan ?</h1><p>Trouvez un professionnel qualifié près de chez vous.</p><div className="search-field white"><Icon name="search" /><input placeholder="Quel service recherchez-vous ?" /></div></div>
    <div className="service-workflows"><button onClick={() => go("intervention")}><span><Icon name="plus" /></span><div><strong>Nouvelle demande</strong><small>Décrire une intervention</small></div></button><button onClick={() => go("service-requests")}><span><Icon name="clock" /></span><div><strong>Suivre mes demandes</strong><small>État et progression</small></div></button></div>
    <SectionTitle>Catégories</SectionTitle><div className="category-grid">{categories.map(c => <button onClick={() => go("directory")} key={c.label} className={c.className}><span><Icon name={c.icon} /></span>{c.label}</button>)}</div>
    <div className="complaint-banner"><span><Icon name="alert" /></span><div><strong>Un problème dans votre logement ?</strong><small>Signalez-le et suivez sa résolution.</small></div><button onClick={() => go("complaint")}><Icon name="chevron" /></button></div>
    <SectionTitle action="Voir tout" onClick={() => go("directory")}>Artisans recommandés</SectionTitle>
    <ProCard image={photos.pro} name="Nabil Ben Ali" specialty="Plombier · Tunis" onClick={() => go("pro")} />
    <ProCard image={photos.pro2} name="Inès Trabelsi" specialty="Électricienne · Ariana" onClick={() => go("pro")} />
  </div></div>;
}

function ProCard({ image, name, specialty, onClick }: { image: string; name: string; specialty: string; onClick: () => void }) {
  return <button className="pro-card" onClick={onClick}><img src={image} alt={name} /><div><strong>{name}</strong><span>{specialty}</span><small><b>★ 4,9</b> (48 avis)</small><em>Disponible aujourd'hui</em></div><Icon name="chevron" /></button>;
}

function ProDetail({ go }: { go: (s: Screen) => void }) {
  const [sent, setSent] = useState(false);
  return <div className="page"><Header title="Profil de l'artisan" back={() => go("services")} /><div className="content">{sent ? <SuccessState icon="tools" title="Demande envoyée !" text="Nabil vous contactera rapidement pour préciser l'intervention." action="Voir mes demandes" onClick={() => go("activity")} /> : <>
    <div className="pro-profile"><img src={photos.pro} alt="Nabil Ben Ali" /><div><h1>Nabil Ben Ali</h1><p>Plombier certifié · Tunis</p><span><b>★ 4,9</b> 48 avis · 126 interventions</span><em>● Disponible aujourd'hui</em></div></div>
    <div className="verified-row"><span><Icon name="check" /> Identité vérifiée</span><span><Icon name="check" /> Artisan certifié</span></div>
    <SectionTitle>À propos</SectionTitle><p className="description">Plombier professionnel avec 8 ans d'expérience. Intervention rapide pour dépannage, installation et rénovation.</p>
    <SectionTitle>Services et tarifs</SectionTitle><div className="service-prices"><span><b>Diagnostic & déplacement</b><strong>30 TND</strong></span><span><b>Réparation de fuite</b><strong>dès 45 TND</strong></span><span><b>Installation sanitaire</b><strong>Sur devis</strong></span></div>
    <SectionTitle>Avis récents</SectionTitle><div className="review"><span className="avatar small">SA</span><div><strong>Sarah M. <b>★★★★★</b></strong><p>Très professionnel et ponctuel. Problème réglé rapidement.</p></div></div>
    <div className="two-actions"><Button kind="secondary" icon="message">Contacter</Button><Button onClick={() => go("intervention")}>Demander une intervention</Button></div>
  </>}</div></div>;
}

function InterventionForm({ go }: { go: (s: Screen) => void }) {
  const [category, setCategory] = useState("Plomberie");
  const [urgency, setUrgency] = useState("Normal");
  const [photosList, setPhotosList] = useState<string[]>([photos.apartment]);
  const [submitted, setSubmitted] = useState(false);
  const [success, setSuccess] = useState(false);
  return <div className="page"><Header title={success ? "Demande envoyée" : "Demande d'intervention"} back={() => go("services")} /><div className="content">{success ? <SuccessState icon="tools" title="Votre demande est envoyée" text="Référence #INT-2025-042. Vous serez informé de chaque changement d'état." action="Suivre ma demande" onClick={() => go("service-requests")} /> : <div className="form-stack intervention-form">
    <div className="form-section-title"><span>1</span><div><strong>Type d'intervention</strong><small>Sélectionnez une catégorie *</small></div></div><div className="intervention-categories">{categories.map(item => <button key={item.label} className={category === item.label ? "selected" : ""} onClick={() => setCategory(item.label)}><Icon name={item.icon} />{item.label}</button>)}</div>
    <div className="form-section-title"><span>2</span><div><strong>Description du problème</strong><small>Donnez les détails utiles *</small></div></div><label className="field-wrap"><textarea placeholder="Ex. Une fuite apparaît sous l'évier depuis ce matin..." /></label>
    <div className="form-section-title"><span>3</span><div><strong>Photos</strong><small>Ajoutez des images du problème</small></div></div><div className="photo-manager compact">{photosList.map((photo,index) => <div key={index}><img src={photo} alt="Aperçu du problème" /><button onClick={() => setPhotosList(photosList.filter((_,itemIndex) => itemIndex !== index))}>×</button></div>)}<button className="add-photo" onClick={() => setPhotosList([...photosList, photos.studio])}><Icon name="camera" /><strong>Ajouter</strong></button></div>
    <label className="field-wrap"><span>Niveau d'urgence *</span><div className="urgency-options">{["Faible","Normal","Élevé","Urgent"].map(item => <button className={urgency === item ? "selected" : ""} onClick={() => setUrgency(item)} key={item}>{item}</button>)}</div></label>
    <div className="form-section-title"><span>4</span><div><strong>Localisation</strong><small>Lieu de l'intervention *</small></div></div><label className="field-wrap"><span>Logement concerné</span><div className="select-field"><div><b>Appartement El Manar 2</b><small>12 rue des Jasmins, Tunis</small></div><Icon name="chevron" /></div></label><div className="split"><Field label="Ville *" value="Tunis" icon="map" /><Field label="Quartier *" value="El Manar 2" /></div><Field label="Adresse *" value="12 rue des Jasmins" icon="map" />
    {submitted && <div className="inline-form-error"><Icon name="alert" size={14} />La description et la localisation sont obligatoires.</div>}<div className="form-actions"><Button kind="secondary" onClick={() => go("services")}>Annuler</Button><Button onClick={() => submitted ? setSuccess(true) : setSubmitted(true)}>Envoyer la demande</Button></div>
  </div>}</div></div>;
}

function ProfessionalDirectory({ go }: { go: (s: Screen) => void }) {
  const [specialty, setSpecialty] = useState("Tous");
  const [location, setLocation] = useState("Tunis");
  const empty = specialty === "Serrurerie" && location === "Sousse";
  return <div className="page"><Header title="Annuaire des intervenants" back={() => go("services")} /><div className="content"><div className="directory-search"><Icon name="search" /><input placeholder="Nom ou spécialité..." /></div><div className="directory-filters"><button onClick={() => setSpecialty(specialty === "Serrurerie" ? "Tous" : "Serrurerie")}><Icon name="tools" size={15} />{specialty}</button><button onClick={() => setLocation(location === "Sousse" ? "Tunis" : "Sousse")}><Icon name="map" size={15} />{location}</button><button><Icon name="star" size={15} />4,5+</button></div><div className="directory-count"><strong>{empty ? "0 professionnel" : "12 professionnels"}</strong><small>Filtres : spécialité, localisation et note</small></div>{empty ? <div className="directory-empty"><span><Icon name="tools" size={29} /></span><strong>Aucun intervenant trouvé</strong><p>Modifiez vos filtres ou envoyez une demande pour être mis en relation.</p><Button onClick={() => go("intervention")}>Créer une demande</Button></div> : <><DirectoryCard image={photos.pro} name="Nabil Ben Ali" specialty="Plombier" area="Tunis, Ariana et La Marsa" price="À partir de 30 TND" rating="4,9 · 48 avis" onProfile={() => go("pro")} onRequest={() => go("intervention")} /><DirectoryCard image={photos.pro2} name="Inès Trabelsi" specialty="Électricienne" area="Ariana et Tunis" price="À partir de 35 TND" rating="4,8 · 31 avis" onProfile={() => go("pro")} onRequest={() => go("intervention")} /><DirectoryCard image={photos.pro} name="Sami Jlassi" specialty="Technicien climatisation" area="Grand Tunis" price="Sur devis" rating="4,7 · 26 avis" onProfile={() => go("pro")} onRequest={() => go("intervention")} /></>}</div></div>;
}

function DirectoryCard({ image, name, specialty, area, price, rating, onProfile, onRequest }: { image: string; name: string; specialty: string; area: string; price: string; rating: string; onProfile: () => void; onRequest: () => void }) {
  return <div className="directory-card"><img src={image} alt={name} /><div className="directory-card-main"><div><strong>{name}</strong><span>{specialty}</span><small><Icon name="map" size={12} />{area}</small><small><Icon name="star" size={12} />{rating}</small><b>{price}</b></div><div><button onClick={onProfile}>Voir le profil</button><button onClick={onRequest}>Demander une intervention</button></div></div></div>;
}

function ServiceRequests({ go }: { go: (s: Screen) => void }) {
  const requests = [
    { ref: "#INT-2025-047", category: "Serrurerie", text: "Serrure de la porte d'entrée bloquée", pro: "Non assigné", date: "Envoyée aujourd'hui · Aucune mise à jour", status: "Demandée" },
    { ref: "#INT-2025-042", category: "Plomberie", text: "Fuite sous l'évier de la cuisine", pro: "Nabil Ben Ali", date: "Envoyée le 16 juin · Mise à jour aujourd'hui", status: "En cours" },
    { ref: "#INT-2025-038", category: "Électricité", text: "Prise murale défectueuse", pro: "Inès Trabelsi", date: "Envoyée le 12 juin · Mise à jour le 14 juin", status: "Acceptée" },
    { ref: "#INT-2025-021", category: "Climatisation", text: "Entretien annuel du climatiseur", pro: "Sami Jlassi", date: "Envoyée le 2 juin · Terminée le 5 juin", status: "Terminée" },
    { ref: "#INT-2025-016", category: "Peinture", text: "Retouche mur du salon", pro: "Non assigné", date: "Envoyée le 25 mai · Annulée le 26 mai", status: "Annulée" },
  ];
  return <div className="page"><Header title="Mes demandes d'intervention" back={() => go("services")} right={<button className="icon-btn" onClick={() => go("intervention")}><Icon name="plus" /></button>} /><div className="content"><div className="service-request-tabs"><button className="active">Toutes</button><button>Actives</button><button>Terminées</button></div>{requests.map(request => <button className="service-request-card" key={request.ref} onClick={() => go(request.status === "Terminée" ? "service-review" : "service-request-detail")}><div><span className={`service-status ${request.status.toLowerCase().replace(" ","-")}`}>{request.status}</span><small>{request.ref}</small></div><strong>{request.category}</strong><p>{request.text}</p><span><Icon name="user" size={14} />{request.pro}</span><em>{request.date}</em><div className="mini-progress">{["Demandée","Acceptée","En cours","Terminée"].map((step,index) => <i className={index <= (request.status === "Terminée" ? 3 : request.status === "En cours" ? 2 : request.status === "Acceptée" ? 1 : 0) ? "done" : ""} key={step} />)}</div>{request.status === "Terminée" && <span className="review-hint"><Icon name="star" size={13} />Noter cette intervention</span>}</button>)}</div></div>;
}

function ServiceRequestDetail({ go }: { go: (s: Screen) => void }) {
  const [cancelled, setCancelled] = useState(false);
  return <div className="page"><Header title="Demande #INT-2025-042" back={() => go("service-requests")} /><div className="content"><div className="request-detail-summary"><div><span className={`service-status ${cancelled ? "annulée" : "en-cours"}`}>{cancelled ? "Annulée" : "En cours"}</span><small>Plomberie</small></div><h1>Fuite sous l'évier de la cuisine</h1><p>Appartement El Manar 2 · Priorité normale</p></div><SectionTitle>Intervenant assigné</SectionTitle><div className="assigned-pro"><img src={photos.pro} alt="Nabil Ben Ali" /><div><strong>Nabil Ben Ali</strong><span>Plombier · ★ 4,9</span><small>Intervention prévue le 19 juin</small></div></div><SectionTitle>Progression</SectionTitle><div className="service-timeline">{["Demandée","Acceptée","En cours","Terminée"].map((step,index) => <div className={index < 3 && !cancelled ? "done" : ""} key={step}><i>{index < 3 && !cancelled && <Icon name="check" size={12} />}</i><div><strong>{step}</strong><small>{index === 0 ? "16 juin, 09:32" : index === 1 ? "17 juin, 16:40" : index === 2 ? "Aujourd'hui, 10:24" : "En attente"}</small></div></div>)}</div><SectionTitle>Dernière mise à jour</SectionTitle><div className="update-note"><Icon name="tools" /><p>Nabil est en route vers le logement. L'intervention est actuellement en cours.</p></div>{!cancelled && <button className="cancel-post" onClick={() => setCancelled(true)}><Icon name="alert" size={17} />Annuler la demande</button>}</div></div>;
}

function ServiceReview({ go }: { go: (s: Screen) => void }) {
  const [rating, setRating] = useState(0); const [sent, setSent] = useState(false);
  return <div className="page"><Header title="Évaluer l'intervention" back={() => go("service-requests")} /><div className="content">{sent ? <SuccessState icon="star" title="Merci pour votre avis !" text="Votre évaluation a bien été enregistrée." action="Retour aux demandes" onClick={() => go("service-requests")} /> : <div className="service-review"><div className="assigned-pro"><img src={photos.pro} alt="Nabil Ben Ali" /><div><strong>Nabil Ben Ali</strong><span>Réparation de fuite</span><small>Intervention terminée le 19 juin</small></div><span className="service-status terminée">Terminée</span></div><h1>Comment s'est passée l'intervention ?</h1><p>Votre avis aide les autres utilisateurs à choisir un professionnel.</p><div className="rating-stars">{[1,2,3,4,5].map(star => <button className={rating >= star ? "active" : ""} onClick={() => setRating(star)} key={star}><Icon name="star" size={32} /></button>)}</div><label className="field-wrap"><span>Votre avis (facultatif)</span><textarea placeholder="Décrivez votre expérience avec cet intervenant..." /></label><Button onClick={() => rating && setSent(true)}>Envoyer mon avis</Button></div>}</div></div>;
}

function ServiceNotifications({ go }: { go: (s: Screen) => void }) {
  const [read, setRead] = useState<number[]>([]);
  const items = [{ text: "Votre demande a été acceptée.", ref: "#INT-2025-038", date: "Aujourd'hui, 09:15", icon: "check" as IconName },{ text: "Votre intervention est en cours.", ref: "#INT-2025-042", date: "Aujourd'hui, 10:24", icon: "tools" as IconName },{ text: "Votre intervention est terminée.", ref: "#INT-2025-021", date: "5 juin, 16:40", icon: "star" as IconName },{ text: "Votre demande a été annulée.", ref: "#INT-2025-016", date: "26 mai, 11:05", icon: "alert" as IconName }];
  return <div className="page"><Header title="Notifications Services" back={() => go("services")} right={<button className="text-button" onClick={() => setRead([0,1,2,3])}>Tout lire</button>} /><div className="content no-top"><div className="notification-day">MISES À JOUR DES INTERVENTIONS</div>{items.map((item,index) => <button className={`notification-item ${!read.includes(index) ? "unread" : ""}`} onClick={() => { setRead([...read,index]); go(index === 2 ? "service-review" : "service-request-detail"); }} key={item.ref}><span className={`notif-icon ${index === 2 ? "mint" : index === 3 ? "rose" : "blue"}`}><Icon name={item.icon} /></span><div><strong>{item.text}</strong><p>Demande {item.ref}</p><small>{item.date}</small></div>{!read.includes(index) && <i />}</button>)}</div></div>;
}

function Complaint({ go }: { go: (s: Screen) => void }) {
  const [sent, setSent] = useState(false); const [category, setCategory] = useState("Fuite d'eau");
  return <div className="page"><Header title={sent ? "Réclamation envoyée" : "Signaler un problème"} back={() => go("services")} /><div className="content">
    {sent ? <SuccessState icon="check" title="Votre réclamation est envoyée" text="Référence #REC-2025-1842. Nous vous tiendrons informé de chaque mise à jour." action="Suivre ma réclamation" onClick={() => go("tracking")} /> : <div className="form-stack">
      <label className="field-wrap"><span>Logement concerné</span><div className="select-field"><div><b>Appartement El Manar 2</b><small>12 rue des Jasmins, Tunis</small></div><Icon name="chevron" /></div></label>
      <label className="field-wrap"><span>Type de problème</span><div className="issue-grid">{["Fuite d'eau","Électricité","Chauffage","Équipement endommagé","Problème propriétaire","Autre"].map((c,i)=><button className={category===c ? "selected" : ""} onClick={() => setCategory(c)} key={c}><Icon name={(["droplet","bolt","snow","tools","user","alert"] as IconName[])[i]} />{c}</button>)}</div></label>
      <label className="field-wrap"><span>Décrivez le problème</span><textarea defaultValue="Une fuite est apparue sous l'évier de la cuisine depuis ce matin." /></label>
      <label className="field-wrap"><span>Ajouter des photos (facultatif)</span><button className="upload"><Icon name="camera" /><b>Ajouter une photo</b><small>PNG ou JPG · 5 Mo max.</small></button></label>
      <label className="field-wrap"><span>Niveau de priorité</span><div className="priority"><button>Faible</button><button className="selected">Moyenne</button><button>Urgente</button></div></label>
      <Button onClick={() => setSent(true)}>Envoyer la réclamation</Button>
    </div>}
  </div></div>;
}

function Tracking({ go }: { go: (s: Screen) => void }) {
  return <div className="page"><Header title="Mes réclamations" back={() => go("services")} right={<button className="icon-btn" onClick={() => go("complaint")}><Icon name="plus" /></button>} /><div className="content">
    <div className="tabs"><button className="active">Toutes</button><button>En cours</button><button>Résolues</button></div>
    <button className="complaint-card" onClick={() => go("complaint-detail")}><div className="complaint-top"><span className="status progress">En cours</span><small>#REC-2025-1842</small></div><strong>Fuite d'eau dans la cuisine</strong><span><Icon name="building" size={15} /> Appartement El Manar 2</span><div><small>Créée le 16 juin 2025</small><Icon name="chevron" /></div></button>
    <button className="complaint-card"><div className="complaint-top"><span className="status waiting">En attente</span><small>#REC-2025-1786</small></div><strong>Climatiseur en panne</strong><span><Icon name="building" size={15} /> Appartement El Manar 2</span><div><small>Créée le 10 juin 2025</small><Icon name="chevron" /></div></button>
    <button className="complaint-card faded"><div className="complaint-top"><span className="status solved">Résolue</span><small>#REC-2025-1654</small></div><strong>Poignée de porte cassée</strong><span><Icon name="building" size={15} /> Appartement El Manar 2</span><div><small>Résolue le 2 juin 2025</small><Icon name="chevron" /></div></button>
  </div></div>;
}

function ComplaintDetail({ go }: { go: (s: Screen) => void }) {
  return <div className="page"><Header title="Réclamation #1842" back={() => go("tracking")} right={<button className="icon-btn"><Icon name="message" /></button>} /><div className="content">
    <div className="complaint-detail-head"><span className="status progress">En cours</span><h1>Fuite d'eau dans la cuisine</h1><p>Appartement El Manar 2 · Priorité moyenne</p></div>
    <SectionTitle>Suivi de la demande</SectionTitle><div className="timeline">
      <div className="done"><i><Icon name="check" size={14} /></i><div><strong>Intervention planifiée</strong><p>Nabil interviendra le 19 juin entre 14h et 16h.</p><small>Aujourd'hui, 10:24</small></div></div>
      <div className="done"><i><Icon name="check" size={14} /></i><div><strong>Artisan assigné</strong><p>Nabil Ben Ali a été assigné à votre demande.</p><small>17 juin, 16:40</small></div></div>
      <div className="done"><i><Icon name="check" size={14} /></i><div><strong>Réclamation prise en charge</strong><p>Votre propriétaire a consulté le signalement.</p><small>16 juin, 12:15</small></div></div>
      <div><i /><div><strong>Réclamation envoyée</strong><p>Votre demande a bien été enregistrée.</p><small>16 juin, 09:32</small></div></div>
    </div>
    <div className="appointment-card"><div className="date-block"><b>19</b><span>JUIN</span></div><div><strong>Intervention de Nabil</strong><span>14:00 – 16:00</span></div><button><Icon name="message" /></button></div>
    <Button kind="secondary" icon="message">Envoyer un message</Button>
  </div></div>;
}

function Activity({ go }: { go: (s: Screen) => void }) {
  const [tab, setTab] = useState("Mes visites");
  const tabs = ["Mes logements","Mes visites","Mes trajets","Mes demandes","Mes réclamations"];
  return <div className="page"><Header title="Mon activité" back={() => go("profile")} /><div className="activity-tabs">{tabs.map(t=><button key={t} className={tab===t ? "active":""} onClick={()=>setTab(t)}>{t}</button>)}</div><div className="content">
    {tab==="Mes visites" && <><SectionTitle>À venir</SectionTitle><div className="activity-card"><img src={photos.apartment} alt="" /><div><span className="status progress">En attente</span><strong>Appartement lumineux S+2</strong><small><Icon name="calendar" size={14} /> Jeudi 19 juin · 11:00</small><small><Icon name="map" size={14} /> El Manar 2, Tunis</small></div></div><SectionTitle>Passées</SectionTitle><div className="empty-small"><Icon name="calendar" /><p>Aucune visite passée</p></div></>}
    {tab==="Mes logements" && <PropertyCard horizontal property={properties[0]} onClick={()=>go("property")} />}
    {tab==="Mes trajets" && <RideCard from="Tunis" to="Sousse" times={["08:00","10:10"]} name="Walid A." price="18" seats={3} onClick={()=>go("ride")} />}
    {tab==="Mes demandes" && <ProCard image={photos.pro} name="Nabil Ben Ali" specialty="Intervention · 19 juin" onClick={()=>go("pro")} />}
    {tab==="Mes réclamations" && <button className="complaint-card" onClick={()=>go("complaint-detail")}><div className="complaint-top"><span className="status progress">En cours</span><small>#REC-2025-1842</small></div><strong>Fuite d'eau dans la cuisine</strong><span>Appartement El Manar 2</span></button>}
  </div></div>;
}

function Notifications({ go }: { go: (s: Screen) => void }) {
  const items: { icon: IconName; className: string; title: string; text: string; time: string; target: Screen }[] = [
    {icon:"calendar",className:"blue",title:"Rappel de visite",text:"Votre visite à El Manar est prévue demain à 11:00.",time:"Il y a 8 min",target:"visit"},
    {icon:"car",className:"mint",title:"Demande de trajet acceptée",text:"Walid a accepté votre demande Tunis → Sousse.",time:"Il y a 1 h",target:"ride"},
    {icon:"tools",className:"purple",title:"Intervention confirmée",text:"Nabil interviendra jeudi entre 14h et 16h.",time:"Hier",target:"complaint-detail"},
    {icon:"alert",className:"amber",title:"Réclamation mise à jour",text:"Votre demande #1842 est maintenant en cours.",time:"Hier",target:"complaint-detail"},
    {icon:"heart",className:"rose",title:"Nouveau logement",text:"Un studio à Ariana correspond à vos favoris.",time:"12 juin",target:"housing"},
  ];
  return <div className="page"><Header title="Notifications" back={()=>go("home")} right={<button className="text-button">Tout lire</button>} /><div className="content no-top"><div className="notification-day">AUJOURD'HUI</div>{items.map((n,i)=><button key={n.title} className={`notification-item ${i<3?"unread":""}`} onClick={()=>go(n.target)}><span className={`notif-icon ${n.className}`}><Icon name={n.icon} /></span><div><strong>{n.title}</strong><p>{n.text}</p><small>{n.time}</small></div>{i<3&&<i />}</button>)}</div></div>;
}

function Profile({ go }: { go: (s: Screen) => void }) {
  const rows: {icon:IconName;label:string;detail?:string;target?:Screen}[] = [
    {icon:"building",label:"Mon activité",detail:"Annonces, visites et demandes",target:"activity"},
    {icon:"heart",label:"Logements enregistrés",detail:"6 favoris",target:"housing"},
    {icon:"bell",label:"Notifications",detail:"3 nouvelles",target:"notifications"},
    {icon:"settings",label:"Paramètres du compte"},
    {icon:"help",label:"Aide et assistance"},
  ];
  return <div className="page profile-page"><Header title="Mon profil" right={<button className="icon-btn"><Icon name="settings" /></button>} /><div className="content">
    <div className="profile-hero"><div className="profile-avatar">IB<button><Icon name="camera" size={14} /></button></div><h1>Islem Ben Salah</h1><p>Étudiante · Université de Tunis</p><span><Icon name="check" size={15} /> Profil vérifié</span></div>
    <div className="profile-stats"><button onClick={()=>go("activity")}><strong>3</strong><span>Activités</span></button><button onClick={()=>go("housing")}><strong>6</strong><span>Favoris</span></button><button><strong>4,9</strong><span>Évaluation</span></button></div>
    <div className="menu-list">{rows.map(r=><button key={r.label} onClick={()=>r.target&&go(r.target)}><span><Icon name={r.icon} /></span><div><strong>{r.label}</strong>{r.detail&&<small>{r.detail}</small>}</div><Icon name="chevron" size={18} /></button>)}</div>
    <button className="logout" onClick={()=>go("welcome")}><Icon name="logout" /> Se déconnecter</button><small className="version">StudentHub · Version 1.0.0</small>
  </div></div>;
}

function SuccessState({ icon, title, text, action, onClick }: { icon: IconName; title: string; text: string; action: string; onClick: () => void }) {
  return <div className="success-state"><div className="success-icon"><Icon name={icon} size={36} /><span><Icon name="check" size={17} /></span></div><h1>{title}</h1><p>{text}</p><div className="success-detail"><Icon name="bell" /><span>Vous recevrez une notification dès qu'il y aura du nouveau.</span></div><Button onClick={onClick}>{action}</Button></div>;
}

export default function App() {
  const [screen, setScreen] = useState<Screen>("welcome");
  const go = (next: Screen) => { setScreen(next); document.querySelector(".app-scroll")?.scrollTo({ top: 0, behavior: "smooth" }); };
  const screens: Record<Screen, ReactNode> = {
    welcome: <Welcome go={go} />, login: <Login go={go} />, register: <Register go={go} />, home: <Home go={go} />, housing: <Housing go={go} />, "add-property": <PropertyForm go={go} />, "edit-property": <PropertyForm go={go} edit />, "housing-history": <HousingHistory go={go} />, property: <Property go={go} />, visit: <Visit go={go} />,
    rides: <Rides go={go} />, "ride-filters": <RideFilters go={go} />, "my-rides": <MyRides go={go} />, ride: <RideDetail go={go} />, "request-detail": <DemandDetail go={go} />, "ride-author": <RideAuthor go={go} />, "ride-rating": <RideRating go={go} />, "ride-notifications": <RideNotifications go={go} />, publish: <PublishRide go={go} />, "publish-request": <PublishRide go={go} initialType="Demande" />, services: <Services go={go} />, intervention: <InterventionForm go={go} />, directory: <ProfessionalDirectory go={go} />, "service-requests": <ServiceRequests go={go} />, "service-request-detail": <ServiceRequestDetail go={go} />, "service-review": <ServiceReview go={go} />, "service-notifications": <ServiceNotifications go={go} />, pro: <ProDetail go={go} />,
    complaint: <Complaint go={go} />, tracking: <Tracking go={go} />, "complaint-detail": <ComplaintDetail go={go} />, activity: <Activity go={go} />,
    notifications: <Notifications go={go} />, profile: <Profile go={go} />,
  };
  const noNav: Screen[] = ["welcome", "login", "register", "add-property", "edit-property", "property", "visit", "ride", "request-detail", "ride-author", "ride-rating", "publish", "publish-request", "ride-filters", "intervention", "service-request-detail", "service-review", "pro", "complaint", "tracking", "complaint-detail", "notifications"];
  return <main className="showcase"><div className="phone-shell"><StatusBar /><div className="app-scroll">{screens[screen]}</div>{!noNav.includes(screen) && <BottomNav screen={screen} go={go} />}<div className="android-home" /></div><div className="prototype-note"><b>StudentHub</b><span>Prototype mobile interactif</span></div></main>;
}
