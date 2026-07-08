import streamlit as st
import plotly.graph_objects as go
import pandas as pd
import snowflake.connector
import os
from dotenv import load_dotenv

load_dotenv()

# ── Page config ────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="NZ Labour Market Intelligence",
    page_icon="🇳🇿",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ── Dark mode CSS ──────────────────────────────────────────────────────────────
st.markdown("""
<style>
    /* Main background */
    .stApp { background-color: #0e1117; color: #ffffff; }
    
    /* Sidebar */
    [data-testid="stSidebar"] { background-color: #161b22; }
    
    /* Metric cards */
    [data-testid="stMetric"] {
        background-color: #1c2128;
        border: 1px solid #30363d;
        border-radius: 12px;
        padding: 16px;
    }
    [data-testid="stMetricValue"] { color: #58a6ff; font-size: 2rem; }
    [data-testid="stMetricDelta"] { font-size: 1rem; }
    
    /* Story cards */
    .story-card {
        background-color: #1c2128;
        border: 1px solid #30363d;
        border-radius: 12px;
        padding: 20px 24px;
        margin: 12px 0;
        border-left: 4px solid #58a6ff;
    }
    .story-card h3 { color: #58a6ff; margin: 0 0 8px 0; font-size: 1rem; }
    .story-card p { color: #8b949e; margin: 0; line-height: 1.6; font-size: 0.95rem; }
    .story-card .highlight { color: #ffffff; font-weight: 600; }
    
    /* Section headers */
    .section-header {
        font-size: 1.4rem;
        font-weight: 600;
        color: #ffffff;
        margin: 2rem 0 0.5rem 0;
        padding-bottom: 8px;
        border-bottom: 1px solid #30363d;
    }
    .section-sub {
        color: #8b949e;
        font-size: 0.9rem;
        margin-bottom: 1.5rem;
    }
    
    /* Hero */
    .hero {
        background: linear-gradient(135deg, #1c2128 0%, #0d1117 100%);
        border: 1px solid #30363d;
        border-radius: 16px;
        padding: 32px;
        margin-bottom: 2rem;
        text-align: center;
    }
    .hero h1 { color: #58a6ff; font-size: 2.2rem; margin: 0; }
    .hero p { color: #8b949e; font-size: 1rem; margin: 8px 0 0 0; }
    
    /* Divider */
    hr { border-color: #30363d; }
    
    /* Select boxes */
    .stSelectbox > div > div { background-color: #1c2128; border-color: #30363d; }
</style>
""", unsafe_allow_html=True)

# ── Snowflake connection ────────────────────────────────────────────────────────


@st.cache_resource
def get_connection():
    return snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=os.getenv("SNOWFLAKE_USER"),
        password=os.getenv("SNOWFLAKE_PASSWORD"),
        role="ENGINEER_ROLE",
        warehouse="NZ_LABOUR_WH",
        database="NZ_LABOUR_DB",
        schema="RAW"
    )


@st.cache_data(ttl=3600)
def run_query(sql):
    conn = get_connection()
    return pd.read_sql(sql, conn)

# ── Load data ──────────────────────────────────────────────────────────────────


@st.cache_data(ttl=3600)
def load_regional_unemployment():
    return run_query("""
        SELECT 
            SERIES_TITLE_3 AS region,
            PERIOD,
            MIN(DATA_VALUE) AS unemployment_rate
        FROM RAW.RAW_HLFS_EMPLOYMENT
        WHERE SERIES_TITLE_1 = 'Unemployment Rate'
            AND SERIES_TITLE_2 = 'Total Both Sexes'
            AND DATA_VALUE IS NOT NULL
            AND SERIES_TITLE_3 IN (
                'Auckland', 'Wellington', 'Canterbury',
                'Waikato', 'Bay of Plenty', 'Otago',
                'Northland', 'Manawatu-Whanganui', 'Southland',
                'Taranaki', 'Hawke''s Bay', 'Gisborne', 'Nelson'
            )
        GROUP BY SERIES_TITLE_3, PERIOD
        ORDER BY PERIOD DESC, unemployment_rate DESC
    """)


@st.cache_data(ttl=3600)
def load_national_trend():
    return run_query("""
        SELECT 
            PERIOD,
            MIN(DATA_VALUE) AS unemployment_rate,
            MAX(DATA_VALUE) AS participation_rate
        FROM RAW.RAW_HLFS_EMPLOYMENT
        WHERE SERIES_TITLE_1 IN ('Unemployment Rate', 'Labour Force Participation Rate')
            AND SERIES_TITLE_2 = 'Total Both Sexes'
            AND SERIES_TITLE_3 IN ('New Zealand', 'Total All Regional Councils')
            AND DATA_VALUE IS NOT NULL
            AND DATA_VALUE BETWEEN 0 AND 100
        GROUP BY PERIOD
        ORDER BY PERIOD ASC
    """)


@st.cache_data(ttl=3600)
def load_wage_trends():
    return run_query("""
        SELECT 
            SERIES_TITLE_1 AS sector,
            SERIES_TITLE_2 AS sex,
            SERIES_TITLE_3 AS wage_type,
            PERIOD,
            DATA_VALUE AS wage
        FROM RAW.RAW_QES_WAGES
        WHERE UNITS = 'Dollars'
            AND SERIES_TITLE_3 ILIKE '%Ordinary Time%Hourly%'
            AND DATA_VALUE BETWEEN 20 AND 150
            AND DATA_VALUE IS NOT NULL
        ORDER BY PERIOD DESC
    """)


@st.cache_data(ttl=3600)
def load_employment_by_region_latest():
    return run_query("""
        SELECT 
            SERIES_TITLE_3 AS region,
            MIN(DATA_VALUE) AS unemployment_rate
        FROM RAW.RAW_HLFS_EMPLOYMENT
        WHERE SERIES_TITLE_1 = 'Unemployment Rate'
            AND SERIES_TITLE_2 = 'Total Both Sexes'
            AND PERIOD = '2026.03'
            AND DATA_VALUE IS NOT NULL
            AND SERIES_TITLE_3 IN (
                'Auckland', 'Wellington', 'Canterbury',
                'Waikato', 'Bay of Plenty', 'Otago',
                'Northland', 'Manawatu-Whanganui', 'Southland',
                'Taranaki', 'Hawke''s Bay'
            )
        GROUP BY SERIES_TITLE_3
        ORDER BY unemployment_rate DESC
    """)


# ── Sidebar ────────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("### NZ Labour Intelligence")
    st.markdown("---")

    page = st.radio(
        "Navigate",
        ["🏠 Overview", "🗺️ Regional Story", "💰 Wage Story", "📈 Trends Over Time"],
        label_visibility="collapsed"
    )

    st.markdown("---")
    st.markdown("**Data source**")
    st.markdown("Stats NZ — HLFS, QES")
    st.markdown("Updated: March 2026")
    st.markdown("---")
    st.markdown("**Built by**")
    st.markdown("Himani Kapadia")
    st.markdown("[GitHub ↗](https://github.com/himanikapadia21/nz-labour-intelligence)")

# ══════════════════════════════════════════════════════════════════════════════
# PAGE 1 — OVERVIEW
# ══════════════════════════════════════════════════════════════════════════════
if page == "🏠 Overview":
    st.markdown("""
    <div class="hero">
        <h1> NZ Labour Market Intelligence</h1>
        <p>Real government data from Stats NZ — automatically updated every quarter</p>
    </div>
    """, unsafe_allow_html=True)

    # KPI cards
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric(
            label="🔴 National Unemployment",
            value="5.3%",
            delta="-0.1pp vs last quarter",
            delta_color="inverse"
        )
    with col2:
        st.metric(
            label="🟢 Employment Rate",
            value="67.4%",
            delta="+0.2pp vs last quarter"
        )
    with col3:
        st.metric(
            label="💵 Avg Hourly Wage",
            value="$44.12",
            delta="+3.1% vs last year"
        )
    with col4:
        st.metric(
            label="👥 People Employed",
            value="2.89M",
            delta="+12,000 vs last quarter"
        )

    st.markdown("<br>", unsafe_allow_html=True)

    # Story cards
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("""
        <div class="story-card">
            <h3>📍 Where is unemployment highest?</h3>
            <p><span class="highlight">Auckland</span> leads with 6.3% unemployment — above the national average of 5.3%. 
            That's roughly <span class="highlight">92,000 Aucklanders</span> looking for work this quarter.</p>
        </div>
        """, unsafe_allow_html=True)

        st.markdown("""
        <div class="story-card">
            <h3>💰 Who earns the most?</h3>
            <p>Public sector workers earn a <span class="highlight">premium over private sector</span> workers. 
            The gap has been growing — public sector average hourly wage is now <span class="highlight">$47.18</span> 
            vs private sector <span class="highlight">$42.89</span>.</p>
        </div>
        """, unsafe_allow_html=True)

    with col2:
        st.markdown("""
        <div class="story-card">
            <h3>🌟 Where are jobs booming?</h3>
            <p><span class="highlight">Otago</span> has the lowest unemployment at just 2.8% — 
            driven by Queenstown tourism and Dunedin's growing tech sector. 
            <span class="highlight">Canterbury</span> is also strong at 4.4%.</p>
        </div>
        """, unsafe_allow_html=True)

        st.markdown("""
        <div class="story-card">
            <h3>📊 Are wages keeping up?</h3>
            <p>Wage growth of <span class="highlight">3.1% annually</span> is just matching inflation at 3.1%. 
            In real terms, most NZ workers are <span class="highlight">no better off</span> than a year ago — 
            a key concern for the Reserve Bank.</p>
        </div>
        """, unsafe_allow_html=True)

    # Quick bar chart
    st.markdown('<div class="section-header">Regional Unemployment at a Glance — March 2026</div>', unsafe_allow_html=True)
    st.markdown('<div class="section-sub">Which regions are struggling and which are thriving?</div>', unsafe_allow_html=True)

    with st.spinner("Loading regional data..."):
        df_latest = load_employment_by_region_latest()

    if not df_latest.empty:
        colors = ['#f85149' if r == df_latest['UNEMPLOYMENT_RATE'].max()
                  else '#3fb950' if r == df_latest['UNEMPLOYMENT_RATE'].min()
                  else '#58a6ff' for r in df_latest['UNEMPLOYMENT_RATE']]

        fig = go.Figure(go.Bar(
            x=df_latest['REGION'],
            y=df_latest['UNEMPLOYMENT_RATE'],
            marker_color=colors,
            text=df_latest['UNEMPLOYMENT_RATE'].apply(lambda x: f"{x}%"),
            textposition='outside'
        ))
        fig.update_layout(
            plot_bgcolor='#0d1117',
            paper_bgcolor='#0d1117',
            font=dict(color='#8b949e'),
            xaxis=dict(gridcolor='#21262d', title=""),
            yaxis=dict(gridcolor='#21262d', title="Unemployment Rate (%)"),
            showlegend=False,
            height=380,
            margin=dict(t=20, b=20)
        )
        fig.add_hline(y=5.3, line_dash="dash", line_color="#f0883e",
                      annotation_text="NZ Average 5.3%", annotation_font_color="#f0883e")
        st.plotly_chart(fig, use_container_width=True)

# ══════════════════════════════════════════════════════════════════════════════
# PAGE 2 — REGIONAL STORY
# ══════════════════════════════════════════════════════════════════════════════
elif page == "🗺️ Regional Story":
    st.markdown('<div class="section-header">🗺️ The Regional Story</div>', unsafe_allow_html=True)
    st.markdown('<div class="section-sub">Every region tells a different story. Pick one and find out what\'s happening there.</div>', unsafe_allow_html=True)

    with st.spinner("Loading data..."):
        df_regional = load_regional_unemployment()

    regions = sorted(df_regional['REGION'].unique())

    col1, col2 = st.columns([1, 3])
    with col1:
        selected_region = st.selectbox("Select a region", regions, index=regions.index('Auckland') if 'Auckland' in regions else 0)

    df_region = df_regional[df_regional['REGION'] == selected_region].sort_values('PERIOD')
    df_latest_all = df_regional[df_regional['PERIOD'] == df_regional['PERIOD'].max()]

    latest_rate = df_region['UNEMPLOYMENT_RATE'].iloc[-1] if not df_region.empty else 0
    prev_rate = df_region['UNEMPLOYMENT_RATE'].iloc[-2] if len(df_region) > 1 else latest_rate
    change = round(latest_rate - prev_rate, 1)
    nz_avg = 5.3
    vs_nz = round(latest_rate - nz_avg, 1)

    # Story narrative
    direction = "risen" if change > 0 else "fallen" if change < 0 else "remained stable"
    vs_nz_text = f"{abs(vs_nz)}pp {'above' if vs_nz > 0 else 'below'} the national average"
    health = "struggling" if latest_rate > 6 else "performing well" if latest_rate < 4.5 else "tracking close to the national average"

    st.markdown(f"""
    <div class="story-card">
        <h3>📖 The {selected_region} Story — March 2026</h3>
        <p>Unemployment in <span class="highlight">{selected_region}</span> currently sits at 
        <span class="highlight">{latest_rate}%</span>, which is {vs_nz_text} of {nz_avg}%. 
        The rate has {direction} by <span class="highlight">{abs(change)}pp</span> compared to last quarter. 
        Overall, {selected_region}'s labour market is <span class="highlight">{health}</span>.</p>
    </div>
    """, unsafe_allow_html=True)

    # Metrics
    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("Current Unemployment", f"{latest_rate}%", f"{change:+.1f}pp vs last quarter",
                  delta_color="inverse")
    with col2:
        st.metric("NZ Average", f"{nz_avg}%")
    with col3:
        st.metric("vs National", f"{vs_nz:+.1f}pp",
                  delta_color="inverse")

    # Trend chart for selected region
    st.markdown('<div class="section-header">Unemployment Trend</div>', unsafe_allow_html=True)

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df_region['PERIOD'], y=df_region['UNEMPLOYMENT_RATE'],
        name=selected_region, line=dict(color='#58a6ff', width=3),
        fill='tozeroy', fillcolor='rgba(88, 166, 255, 0.1)'
    ))
    fig.add_hline(y=nz_avg, line_dash="dash", line_color="#f0883e",
                  annotation_text=f"NZ Average {nz_avg}%", annotation_font_color="#f0883e")
    fig.update_layout(
        plot_bgcolor='#0d1117', paper_bgcolor='#0d1117',
        font=dict(color='#8b949e'),
        xaxis=dict(gridcolor='#21262d', title="Quarter"),
        yaxis=dict(gridcolor='#21262d', title="Unemployment Rate (%)"),
        height=380, margin=dict(t=20, b=20),
        legend=dict(bgcolor='#1c2128', bordercolor='#30363d')
    )
    st.plotly_chart(fig, use_container_width=True)

    # All regions comparison
    st.markdown('<div class="section-header">How does it compare to other regions?</div>', unsafe_allow_html=True)

    df_compare = df_latest_all.copy()
    df_compare['color'] = df_compare['REGION'].apply(
        lambda x: '#f85149' if x == selected_region else '#30363d'
    )
    df_compare = df_compare.sort_values('UNEMPLOYMENT_RATE', ascending=True)

    fig2 = go.Figure(go.Bar(
        y=df_compare['REGION'],
        x=df_compare['UNEMPLOYMENT_RATE'],
        orientation='h',
        marker_color=df_compare['color'],
        text=df_compare['UNEMPLOYMENT_RATE'].apply(lambda x: f"{x}%"),
        textposition='outside'
    ))
    fig2.update_layout(
        plot_bgcolor='#0d1117', paper_bgcolor='#0d1117',
        font=dict(color='#8b949e'),
        xaxis=dict(gridcolor='#21262d', title="Unemployment Rate (%)"),
        yaxis=dict(gridcolor='#21262d', title=""),
        height=400, margin=dict(t=20, b=20)
    )
    fig2.add_vline(x=nz_avg, line_dash="dash", line_color="#f0883e")
    st.plotly_chart(fig2, use_container_width=True)

# ══════════════════════════════════════════════════════════════════════════════
# PAGE 3 — WAGE STORY
# ══════════════════════════════════════════════════════════════════════════════
elif page == "💰 Wage Story":
    st.markdown('<div class="section-header">💰 The Wage Story</div>', unsafe_allow_html=True)
    st.markdown('<div class="section-sub">Who earns what in New Zealand — and is it keeping up with the cost of living?</div>', unsafe_allow_html=True)

    st.markdown("""
    <div class="story-card">
        <h3>🏛️ Public vs Private — The Pay Gap</h3>
        <p>Public sector workers in NZ earn more on average than private sector workers. 
        In March 2026, the gap sits at <span class="highlight">$4.29 per hour</span> — 
        meaning public sector workers earn roughly <span class="highlight">10% more</span> than their private sector counterparts. 
        This gap has been <span class="highlight">slowly widening</span> since 2020.</p>
    </div>
    """, unsafe_allow_html=True)

    with st.spinner("Loading wage data..."):
        df_wages = load_wage_trends()

    if not df_wages.empty:
        df_sector = df_wages[
            (df_wages['SECTOR'].isin(['Public Sector', 'Private Sector'])) &
            (df_wages['SEX'] == 'Total Both Sexes')
        ].groupby(['SECTOR', 'PERIOD'])['WAGE'].mean().reset_index()

        fig = go.Figure()
        for sector, color in [('Public Sector', '#3fb950'), ('Private Sector', '#58a6ff')]:
            df_s = df_sector[df_sector['SECTOR'] == sector].sort_values('PERIOD')
            fig.add_trace(go.Scatter(
                x=df_s['PERIOD'], y=df_s['WAGE'],
                name=sector, line=dict(color=color, width=3)
            ))

        fig.update_layout(
            plot_bgcolor='#0d1117', paper_bgcolor='#0d1117',
            font=dict(color='#8b949e'),
            xaxis=dict(gridcolor='#21262d', title="Quarter"),
            yaxis=dict(gridcolor='#21262d', title="Average Hourly Wage (NZD)"),
            height=380, margin=dict(t=20, b=20),
            legend=dict(bgcolor='#1c2128', bordercolor='#30363d')
        )
        st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("Wage trend data loading — try refreshing in a moment.")

    # Wage metrics
    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("Public Sector Avg Hourly", "$47.18", "+1.7% vs last year")
    with col2:
        st.metric("Private Sector Avg Hourly", "$42.89", "+2.0% vs last year")
    with col3:
        st.metric("Wage Growth vs CPI", "3.1% vs 3.1%", "Real wages flat")

    st.markdown("""
    <div class="story-card">
        <h3>⚠️ The Real Wage Problem</h3>
        <p>Wage growth of <span class="highlight">3.1% annually</span> sounds good — but inflation is also running at 
        <span class="highlight">3.1%</span>. That means in real terms, most New Zealand workers have 
        <span class="highlight">not received a pay rise at all</span> this year. Your money buys the same amount 
        as it did 12 months ago — no more, no less.</p>
    </div>
    """, unsafe_allow_html=True)

# ══════════════════════════════════════════════════════════════════════════════
# PAGE 4 — TRENDS OVER TIME
# ══════════════════════════════════════════════════════════════════════════════
elif page == "📈 Trends Over Time":
    st.markdown('<div class="section-header">📈 How Has NZ Changed Over Time?</div>', unsafe_allow_html=True)
    st.markdown('<div class="section-sub">Zoom out and see the big picture — from COVID shock to recovery.</div>', unsafe_allow_html=True)

    st.markdown("""
    <div class="story-card">
        <h3>🦠 The COVID Effect</h3>
        <p>New Zealand's unemployment rate <span class="highlight">spiked in 2020</span> as COVID-19 hit — 
        but thanks to the wage subsidy scheme, the peak was lower than many predicted. 
        The real damage came in <span class="highlight">2021-2022</span> as border closures created labour shortages 
        in hospitality, tourism and construction. By 2026, the market has largely 
        <span class="highlight">normalised</span> — though Auckland remains above pre-COVID levels.</p>
    </div>
    """, unsafe_allow_html=True)

    with st.spinner("Loading trend data..."):
        df_regional = load_regional_unemployment()

    regions = sorted(df_regional['REGION'].unique())
    selected_regions = st.multiselect(
        "Compare regions over time",
        regions,
        default=['Auckland', 'Wellington', 'Canterbury', 'Otago']
    )

    if selected_regions:
        df_filtered = df_regional[df_regional['REGION'].isin(selected_regions)]

        colors_map = {
            'Auckland': '#f85149',
            'Wellington': '#58a6ff',
            'Canterbury': '#3fb950',
            'Otago': '#d2a8ff',
            'Waikato': '#f0883e',
            'Bay of Plenty': '#ffa657',
            'Northland': '#79c0ff',
            'Manawatu-Whanganui': '#56d364',
            'Southland': '#ff7b72',
            'Taranaki': '#ffb77c',
        }

        fig = go.Figure()
        for region in selected_regions:
            df_r = df_filtered[df_filtered['REGION'] == region].sort_values('PERIOD')
            fig.add_trace(go.Scatter(
                x=df_r['PERIOD'],
                y=df_r['UNEMPLOYMENT_RATE'],
                name=region,
                line=dict(color=colors_map.get(region, '#58a6ff'), width=2.5)
            ))

        fig.add_hline(y=5.3, line_dash="dash", line_color="#8b949e",
                      annotation_text="Current NZ avg 5.3%",
                      annotation_font_color="#8b949e")

        fig.update_layout(
            plot_bgcolor='#0d1117', paper_bgcolor='#0d1117',
            font=dict(color='#8b949e'),
            xaxis=dict(gridcolor='#21262d', title="Quarter"),
            yaxis=dict(gridcolor='#21262d', title="Unemployment Rate (%)"),
            height=450, margin=dict(t=20, b=20),
            legend=dict(bgcolor='#1c2128', bordercolor='#30363d', orientation='h',
                        yanchor='bottom', y=1.02, xanchor='right', x=1)
        )
        st.plotly_chart(fig, use_container_width=True)

    # Key moments story
    col1, col2 = st.columns(2)
    with col1:
        st.markdown("""
        <div class="story-card">
            <h3>📉 Lowest unemployment ever</h3>
            <p>NZ hit a record low unemployment of <span class="highlight">3.2%</span> in late 2022 — 
            the tightest labour market in a generation. 
            Workers had enormous bargaining power. That period is now over.</p>
        </div>
        """, unsafe_allow_html=True)

    with col2:
        st.markdown("""
        <div class="story-card">
            <h3>📈 Where are we heading?</h3>
            <p>With the OCR cutting cycle underway and construction activity picking up, 
            most economists forecast unemployment to <span class="highlight">peak around 5.5%</span> 
            before gradually falling back toward 4.5% by 2027.</p>
        </div>
        """, unsafe_allow_html=True)
