package com.example.AlimentaRed.Entity;

import com.example.AlimentaRed.Entity.Enum.EstadoSolicitud;
import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "solicitud")

public class Solicitud {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idSolicitud;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "lote_id")
    private Lote lote;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EstadoSolicitud estado;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "organizacion_id")
    private Organizacion organizacion;

    @Column(nullable = false)
    private int cantidadDisponible;
}