package com.example.AlimentaRed.Entity;

import com.example.AlimentaRed.Entity.Enum.EstadoAlimento;
import com.example.AlimentaRed.Entity.Enum.EstadoLote;
import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDate;

@Data
@Entity
@Table(name = "lote")

public class Lote {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idLote;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "categoria_id")
    private TipoAlimento categoria;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "donante_id")
    private Organizacion donante;

    @Column(nullable = false)
    private int cantidadDisponible;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EstadoLote estado;

    @Enumerated(EnumType.STRING)
    private EstadoAlimento estadoAlimento;

    @Column(nullable = false)
    private LocalDate fechaRegistro;

    @Column(nullable = false)
    private LocalDate fechaCaducidad;
}